# RunManifest.Tests.ps1 - the run manifest (F-008): a metadata-only record of every cmdlet
# the read-only chokepoint dispatched, written alongside the report. Dimension B: a new
# on-disk artifact must not widen the data surface, so a negative test pins that arguments
# and content never appear. Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:RepoRoot 'PurviewPostureAnalyzer.psd1') -Force

    # A no-tenant run is a fully DEGRADED run - every collector read is CommandNotFound.
    # That is exactly the case the manifest is most valuable for; run it once and reuse.
    $script:OutDir = Join-Path ([System.IO.Path]::GetTempPath()) ('ppa-manifest-' + [guid]::NewGuid().ToString('N'))
    $script:Result = Invoke-PurviewPostureAnalyzer -OutputDirectory $script:OutDir -WarningAction SilentlyContinue
    $script:ManifestText = if ($script:Result.ManifestPath -and (Test-Path -LiteralPath $script:Result.ManifestPath)) {
        [System.IO.File]::ReadAllText($script:Result.ManifestPath, [System.Text.Encoding]::UTF8)
    } else { '' }
    # pwsh 7's ConvertFrom-Json auto-converts ISO date strings to [datetime]; PS 5.1 keeps
    # them as strings. So timestamp FORMAT is asserted on the raw on-disk text (engine-neutral),
    # and the parsed object is used only for the non-date fields.
    $script:Manifest = if ($script:ManifestText) { $script:ManifestText | ConvertFrom-Json } else { $null }
}

AfterAll {
    if ($script:OutDir -and (Test-Path -LiteralPath $script:OutDir)) {
        Remove-Item -LiteralPath $script:OutDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module PurviewPostureAnalyzer -Force -ErrorAction SilentlyContinue
}

Describe 'Run manifest (F-008)' {
    It 'is emitted by default alongside the report and returned as ManifestPath' {
        $script:Result.ManifestPath | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:Result.ManifestPath | Should -BeTrue
        [System.IO.Path]::GetFileName($script:Result.ManifestPath) | Should -Be 'posture-run-manifest.json'
        # Written to the same folder as the report (Outputs/... -> gitignored on default runs).
        Split-Path -Parent $script:Result.ManifestPath | Should -Be (Split-Path -Parent $script:Result.HtmlPath)
    }
    It 'carries the run header: start/end, PPA version, PowerShell edition + version' {
        $script:Manifest.tool | Should -Be 'PurviewPostureAnalyzer'
        # ISO-8601 UTC timestamps asserted on the on-disk text (engine-neutral).
        $script:ManifestText | Should -Match '"startedAt":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
        $script:ManifestText | Should -Match '"endedAt":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
        $script:Manifest.startedAt | Should -Not -BeNullOrEmpty
        $script:Manifest.endedAt   | Should -Not -BeNullOrEmpty
        $script:Manifest.ppaVersion | Should -Not -BeNullOrEmpty
        $script:Manifest.powerShell.edition | Should -Not -BeNullOrEmpty
        $script:Manifest.powerShell.version | Should -Not -BeNullOrEmpty
    }
    It 'lists the cmdlets the chokepoint dispatched, each with a status and count' {
        @($script:Manifest.cmdlets).Count | Should -BeGreaterThan 0
        # The run-context probe and the label/audit collector reads are all recorded.
        @($script:Manifest.cmdlets.cmdlet) | Should -Contain 'Get-AcceptedDomain'
        @($script:Manifest.cmdlets.cmdlet) | Should -Contain 'Get-Label'
        @($script:Manifest.cmdlets.cmdlet) | Should -Contain 'Get-OrganizationConfig'
        foreach ($e in @($script:Manifest.cmdlets)) {
            $e.cmdlet | Should -Not -BeNullOrEmpty
            $e.status | Should -Not -BeNullOrEmpty
            $e.at | Should -Not -BeNullOrEmpty
            [int]$e.count | Should -BeGreaterOrEqual 0
        }
        # entry timestamps are ISO-8601 UTC in the written artifact (asserted on raw text).
        $script:ManifestText | Should -Match '"at":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
    }
    It 'is produced on a DEGRADED run (no session): every read recorded as CommandNotFound, count 0' {
        $script:Manifest | Should -Not -BeNullOrEmpty
        $notOk = @($script:Manifest.cmdlets | Where-Object { $_.status -ne 'Ok' })
        $notOk.Count | Should -BeGreaterThan 0
        foreach ($e in @($script:Manifest.cmdlets)) {
            $e.status | Should -Be 'CommandNotFound'
            [int]$e.count | Should -Be 0
        }
    }
    It 'NEGATIVE: records metadata only - cmdlet arguments/filter strings NEVER reach the manifest' {
        $m = InModuleScope PurviewPostureAnalyzer {
            Initialize-PpaRunManifest
            # A read with argument values that look like tenant content/identifiers.
            $null = Invoke-PpaReadCmdlet -Name 'Get-NonexistentPpaProbe' -Arguments @{
                Identity = 'SENTINEL-tenant-secret-42'
                Filter   = "Name -eq 'ConfidentialHRPolicy'"
            }
            Get-PpaRunManifest -PpaVersion '2.0'
        }
        $entry = @($m.cmdlets | Where-Object { $_.cmdlet -eq 'Get-NonexistentPpaProbe' })[0]
        $entry | Should -Not -BeNullOrEmpty
        $entry.status | Should -Be 'CommandNotFound'
        # Entries carry ONLY these four metadata keys - no arguments/data/error field.
        @($entry.PSObject.Properties.Name | Sort-Object) | Should -Be @('at', 'cmdlet', 'count', 'status')
        # The argument values appear NOWHERE in the serialized manifest.
        $json = ConvertTo-Json -InputObject $m -Depth 8
        $json | Should -Not -Match 'SENTINEL-tenant-secret-42'
        $json | Should -Not -Match 'ConfidentialHRPolicy'
        $json | Should -Not -Match '(?i)identity'
        $json | Should -Not -Match '(?i)filter'
    }
    It 'REDACTION: metadata-only, so nothing is redactable - a redacted run emits the same cmdlet list with no redaction tokens' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ppa-manifest-redact-' + [guid]::NewGuid().ToString('N'))
        try {
            $r = Invoke-PurviewPostureAnalyzer -OutputDirectory $tmp -Redact -RedactNames -WarningAction SilentlyContinue
            $txt = [System.IO.File]::ReadAllText($r.ManifestPath, [System.Text.Encoding]::UTF8)
            $txt | Should -Match 'Get-Label'          # cmdlet names present, unredacted
            $txt | Should -Not -Match '\[redacted'    # no domain/UPN masking tokens
            $txt | Should -Not -Match 'Policy-\d\d'   # no name-pseudonym tokens
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
