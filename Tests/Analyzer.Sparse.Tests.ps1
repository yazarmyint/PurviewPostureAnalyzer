# Analyzer.Sparse.Tests.ps1 - regression tests for sparse/empty real-tenant data.
# Root cause on a live tenant (2026-07-01): mandatory [string[]] binding rejected empty
# cells ("Cannot bind argument to parameter 'Cells' because it is an empty string") when
# labels had empty ParentId/scope and Get-DlpComplianceRule returned 0 objects for 6
# policies. These tests pin: (1) empty cells bind and render as a dash, (2) every analyzer
# survives sparse AND zero-object input, (3) empty data never produces a false verdict.
# Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    foreach ($m in 'PpaStatus', 'New-PpaFinding', 'New-PpaSection', 'ConvertTo-PpaNormalized') { . (Join-Path $script:RepoRoot "Private\Model\$m.ps1") }
    foreach ($a in (Get-ChildItem (Join-Path $script:RepoRoot 'Private\Analyze') -Filter '*.ps1')) { . $a.FullName }
    . (Join-Path $script:RepoRoot 'Private\Render\PpaHtml.ps1')
    . (Join-Path $script:RepoRoot 'Private\Render\Export-PpaHtmlReport.ps1')

    function SparseRaw($n) { [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot "Samples\sample-raw\sparse\$n.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json }
    function Assert-ValidSection($sec) {
        @($sec.findings).Count | Should -BeGreaterThan 0
        foreach ($f in $sec.findings) { Test-PpaStatus $f.status | Should -BeTrue }
    }
    . (Join-Path $script:RepoRoot 'Private\Core\Get-PpaLicenseRequirements.ps1')
    $script:Map = Get-PpaLicenseRequirements -Path (Join-Path $script:RepoRoot 'Data\license-requirements.json')
}

Describe 'Model - empty cells are legal' {
    It 'New-PpaRow binds an empty-string cell (the live-tenant throw)' {
        { New-PpaRow -Cells @('Policy name', '', 'x') -Status 'OK' } | Should -Not -Throw
    }
    It 'normalizes null cells to empty strings' {
        (New-PpaRow -Cells ([string[]]@('a', $null)) -Status 'OK').cells[1] | Should -Be ''
    }
}

Describe 'Renderer - empty cells become a dash placeholder' {
    It 'renders an empty cell as &#8212; not a blank hole' {
        $t = New-PpaTable -Columns @('A', 'B', 'Status') -Rows @((New-PpaRow -Cells @('x', '') -Status 'OK'))
        (Write-PpaDetailTable $t) | Should -Match '<td>&#8212;</td>'
    }
}

Describe 'Labels analyzer - sparse tenant data' {
    BeforeAll {
        $script:LabSec = Invoke-PpaLabelAnalyzer -Raw (SparseRaw 'labels-sparse') -AsOf ([datetime]'2026-07-01')
    }
    It 'does not throw and yields valid statuses' { Assert-ValidSection $script:LabSec }
    It 'handles a policy with no labels and no derivable scope (empty cells)' {
        $f02 = $script:LabSec.findings | Where-Object { $_.id -eq 'LABELS-02' }
        $f02.status | Should -Be 'OK'
        $f02.table.rows[0].cells[1] | Should -Be ''
        $f02.table.rows[0].cells[2] | Should -Be ''
    }
    It 'zero auto-label policies -> Recommendation (not a throw)' {
        ($script:LabSec.findings | Where-Object { $_.id -eq 'LABELS-03' }).status | Should -Be 'Recommendation'
    }
    It 'a label with no scopes renders an empty scope cell' {
        $f01 = $script:LabSec.findings | Where-Object { $_.id -eq 'LABELS-01' }
        ($f01.table.rows | Where-Object { $_.cells[0] -eq 'General' }).cells[2] | Should -Be ''
    }
}

Describe 'DLP analyzer - sparse tenant data (0 rules for 6 policies)' {
    BeforeAll {
        $script:DlpSec = Invoke-PpaDlpAnalyzer -Raw (SparseRaw 'dlp-sparse') -AsOf ([datetime]'2026-07-01') -LicenseMap $script:Map
    }
    It 'does not throw and yields valid statuses' { Assert-ValidSection $script:DlpSec }
    It 'DLP-01 lists all six policies with empty SIT cells' {
        $f01 = $script:DlpSec.findings | Where-Object { $_.id -eq 'DLP-01' }
        @($f01.table.rows | Where-Object { -not $_.remark -or $_.cells }).Count | Should -Be 6
        ($f01.table.rows | Where-Object { $_.cells[0] -eq 'Lab Policy 1' }).cells[1] | Should -Be ''
    }
    It 'a policy with zero locations renders Enforcing without a dangling separator' {
        $f01 = $script:DlpSec.findings | Where-Object { $_.id -eq 'DLP-01' }
        ($f01.table.rows | Where-Object { $_.cells[0] -like 'Lab Policy 5*' }).cells[2] | Should -Be 'Enforcing'
    }
    It 'DLP-04 with no HIPAA SITs anywhere is Informational, not a throw or false verdict' {
        ($script:DlpSec.findings | Where-Object { $_.id -eq 'DLP-04' }).status | Should -Be 'Informational'
    }
}

Describe 'Retention analyzer - sparse tenant data (0 retention rules)' {
    BeforeAll {
        $script:RetSec = Invoke-PpaRetentionAnalyzer -Raw (SparseRaw 'retention-sparse')
    }
    It 'does not throw and yields valid statuses' { Assert-ValidSection $script:RetSec }
    It 'RET-03 with zero labels is Informational - never a false "all auto-apply" OK' {
        $f03 = $script:RetSec.findings | Where-Object { $_.id -eq 'RET-03' }
        $f03.status | Should -Be 'Informational'
        $f03.title | Should -Be 'No retention labels defined'
    }
    It 'RET-01 policies with empty label lists render (empty cell, no throw)' {
        ($script:RetSec.findings | Where-Object { $_.id -eq 'RET-01' }).table.rows[0].cells[1] | Should -Be ''
    }
}

Describe 'All eight analyzers - zero-object collector results' {
    It 'Labels: all-empty input produces the no-taxonomy Improvement path' {
        $raw = [pscustomobject]@{
            labels = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() }
            policies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() }
            autoLabels = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() }
            containers = [pscustomobject]@{ status = 'NotCollected'; groups = $null; sites = $null }
        }
        $sec = Invoke-PpaLabelAnalyzer -Raw $raw
        Assert-ValidSection $sec
        ($sec.findings | Where-Object { $_.id -eq 'LABELS-01' }).status | Should -Be 'Improvement'
    }
    It 'DLP: zero policies -> Improvement, no throw' {
        $raw = [pscustomobject]@{
            policies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() }
            rules = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() }
        }
        $sec = Invoke-PpaDlpAnalyzer -Raw $raw -LicenseMap $script:Map
        Assert-ValidSection $sec
        ($sec.findings | Where-Object { $_.id -eq 'DLP-01' }).status | Should -Be 'Improvement'
    }
    It 'Retention: zero everything -> valid statuses, no throw' {
        $raw = [pscustomobject]@{
            policies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() }
            labels = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() }
            adaptiveScopes = [pscustomobject]@{ status = 'Ok'; count = 0 }
        }
        Assert-ValidSection (Invoke-PpaRetentionAnalyzer -Raw $raw)
    }
    It 'Audit: null (unread) flag -> Verify manually, never a false "Disabled"' {
        $raw = [pscustomobject]@{ status = 'CommandNotFound'; error = 'x'; unifiedAuditEnabled = $null; orgStatus = 'CommandNotFound' }
        $sec = Invoke-PpaAuditAnalyzer -Raw $raw -LicenseMap $script:Map
        Assert-ValidSection $sec
        ($sec.findings | Where-Object { $_.id -eq 'AUD-01' }).status | Should -Be 'Verify manually'
        $sec.glance.metric | Should -Be 'Unknown'
    }
    It 'eDiscovery: zero cases -> Informational inventory, no throw' {
        $raw = [pscustomobject]@{ cases = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() } }
        $sec = Invoke-PpaEdiscoveryAnalyzer -Raw $raw -LicenseMap $script:Map
        Assert-ValidSection $sec
        ($sec.findings | Where-Object { $_.id -eq 'ED-01' }).status | Should -Be 'Informational'
    }
    It 'IRM: null count (enumeration unavailable) -> Verify manually, never a claimed zero' {
        $raw = [pscustomobject]@{ policies = [pscustomobject]@{ status = 'CommandNotFound'; error = 'x'; count = $null } }
        $sec = Invoke-PpaInsiderRiskAnalyzer -Raw $raw -LicenseMap $script:Map
        Assert-ValidSection $sec
        $f = $sec.findings | Where-Object { $_.id -eq 'IRM-01' }
        $f.status | Should -Be 'Verify manually'
        $f.table.rows[0].cells[1] | Should -Match 'Not readable'
        $sec.glance.metric | Should -Be 'not readable'
    }
    It 'CC: null count (read did not complete) -> Verify manually' {
        $raw = [pscustomobject]@{ policies = [pscustomobject]@{ status = 'Error'; error = 'x'; count = $null } }
        $sec = Invoke-PpaCommsComplianceAnalyzer -Raw $raw -LicenseMap $script:Map
        Assert-ValidSection $sec
        $f = $sec.findings | Where-Object { $_.id -eq 'CC-01' }
        $f.status | Should -Be 'Verify manually'
        $f.table.rows[0].cells[1] | Should -Match 'Not readable'
    }
    It 'DSPM: one audit-mode policy with empty SITs -> valid statuses, no throw' {
        $raw = [pscustomobject]@{ copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(
            [pscustomobject]@{ name = 'DSPM for AI - Default'; mode = 'AuditAndNotify'; sits = @() }
        ) } }
        $sec = Invoke-PpaDspmAiAnalyzer -Raw $raw -LicenseMap $script:Map -HasSiteLabels:$false
        Assert-ValidSection $sec
        ($sec.findings | Where-Object { $_.id -eq 'AI-02' }).table.rows[0].cells[1] | Should -Be ''
    }
}

Describe 'End-to-end render of sparse sections' {
    It 'renders the sparse Labels+DLP+Retention sections to HTML with dash placeholders' {
        $sections = @(
            Invoke-PpaLabelAnalyzer -Raw (SparseRaw 'labels-sparse') -AsOf ([datetime]'2026-07-01')
            Invoke-PpaDlpAnalyzer -Raw (SparseRaw 'dlp-sparse') -AsOf ([datetime]'2026-07-01') -LicenseMap $script:Map
            Invoke-PpaRetentionAnalyzer -Raw (SparseRaw 'retention-sparse')
        )
        $meta = [pscustomobject]@{ reportTitle = 'T'; version = '2.0'; versionDate = 'June 2026'; dateDisplay = 'x'; organization = 'o'; tenant = 't'; operator = 'op'; mode = 'm' }
        $lic  = [pscustomobject]@{ summary = 's'; note = 'n' }
        $norm = ConvertTo-PpaNormalized -Meta $meta -Licensing $lic -Sections $sections
        $html = Export-PpaHtmlReport -Normalized $norm
        $html | Should -Match '&#8212;'
        ($html.ToCharArray() | Where-Object { [int][char]$_ -gt 126 }).Count | Should -Be 0
    }
}
