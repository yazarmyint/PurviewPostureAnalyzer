# Module.Tests.ps1 - the module imports, exports the public surface, and the orchestrator
# runs end-to-end with graceful degradation (no tenant) producing a full report.
# Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:RepoRoot 'PurviewPostureAnalyzer.psd1') -Force
    $script:OutDir = Join-Path ([System.IO.Path]::GetTempPath()) ('ppa-test-' + [guid]::NewGuid().ToString('N'))
    $script:Result = Invoke-PurviewPostureAnalyzer -OutputDirectory $script:OutDir -Organization 'Test Org' -WarningAction SilentlyContinue
}

AfterAll {
    if ($script:OutDir -and (Test-Path -LiteralPath $script:OutDir)) {
        Remove-Item -LiteralPath $script:OutDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module PurviewPostureAnalyzer -Force -ErrorAction SilentlyContinue
}

Describe 'Module surface' {
    It 'exports exactly the three public functions' {
        $exported = (Get-Command -Module PurviewPostureAnalyzer | Select-Object -ExpandProperty Name | Sort-Object)
        $exported | Should -Be @('Connect-PurviewPostureSession', 'Disconnect-PurviewPostureSession', 'Invoke-PurviewPostureAnalyzer')
    }
    It 'does not leak private helpers to the global scope' {
        Get-Command -Name 'Invoke-PpaLabelAnalyzer' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Orchestrator - graceful degradation with no tenant' {
    It 'writes an HTML report and a JSON export' {
        Test-Path -LiteralPath $script:Result.HtmlPath | Should -BeTrue
        Test-Path -LiteralPath $script:Result.JsonPath | Should -BeTrue
    }
    It 'renders all eight workload sections' {
        @($script:Result.Normalized.sections).Count | Should -Be 8
    }
    It 'produces ASCII-only HTML output' {
        $html = [System.IO.File]::ReadAllText($script:Result.HtmlPath)
        ($html.ToCharArray() | Where-Object { [int][char]$_ -gt 126 }).Count | Should -Be 0
    }
    It 'carries the static license-context note (annotation, not detection)' {
        $script:Result.Normalized.licensing.note | Should -Match 'does not read the tenant'
    }
}

Describe 'No license-confirmation language (assume-E5 model, decision D9)' {
    It 'contains no "not confirmed" / "not available under current licensing" / "not licensed" strings in the product surface' {
        $paths = @('Public', 'Private', 'Data', 'Samples\sample-normalized.json') | ForEach-Object { Join-Path $script:RepoRoot $_ }
        $hits = New-Object System.Collections.Generic.List[string]
        foreach ($p in $paths) {
            $files = if (Test-Path -LiteralPath $p -PathType Container) { Get-ChildItem -LiteralPath $p -Recurse -File -Include *.ps1, *.json } else { Get-Item -LiteralPath $p }
            foreach ($file in $files) {
                $text = [System.IO.File]::ReadAllText($file.FullName)
                foreach ($m in [regex]::Matches($text, '(?i)licens\w* not confirmed|not available under current licensing|not licensed')) {
                    $hits.Add(("{0}: {1}" -f $file.Name, $m.Value))
                }
            }
        }
        $hits -join "`n" | Should -BeNullOrEmpty
    }
}

Describe 'No-Graph guard (decision D9)' {
    It 'contains no Microsoft Graph cmdlets or module references anywhere in the module' {
        $dirs = @('Public', 'Private') | ForEach-Object { Join-Path $script:RepoRoot $_ }
        $hits = New-Object System.Collections.Generic.List[string]
        foreach ($dir in $dirs) {
            foreach ($file in Get-ChildItem -LiteralPath $dir -Recurse -Filter *.ps1) {
                $code = [System.IO.File]::ReadAllText($file.FullName) -replace '(?m)#.*$', ''
                foreach ($m in [regex]::Matches($code, '(?i)\b(Get|Connect|Disconnect)-Mg[A-Za-z]+|Microsoft\.Graph')) {
                    $hits.Add(("{0}: {1}" -f $file.Name, $m.Value))
                }
            }
        }
        $hits -join "`n" | Should -BeNullOrEmpty
    }
}

Describe 'Orchestrator - output path resolution' {
    It 'resolves a RELATIVE -OutputDirectory against the caller location and writes the files' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ppa-rel-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        Push-Location $tmp
        try {
            $r = Invoke-PurviewPostureAnalyzer -OutputDirectory '.\Outputs' -WarningAction SilentlyContinue
            Test-Path -LiteralPath $r.HtmlPath | Should -BeTrue
            Test-Path -LiteralPath $r.JsonPath | Should -BeTrue
            # Must resolve under the pushed location, not the user home.
            $r.HtmlPath | Should -BeLike "*$([System.IO.Path]::GetFileName($tmp))*"
        }
        finally {
            Pop-Location
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes to an ABSOLUTE -OutputDirectory' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ppa-abs-' + [guid]::NewGuid().ToString('N'))
        try {
            $r = Invoke-PurviewPostureAnalyzer -OutputDirectory $tmp -WarningAction SilentlyContinue
            Test-Path -LiteralPath $r.HtmlPath | Should -BeTrue
            Test-Path -LiteralPath $r.JsonPath | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Orchestrator - collector errors are surfaced, not hidden' {
    It 'writes the real collector exception into the degraded section remark' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ppa-err-' + [guid]::NewGuid().ToString('N'))
        try {
            $sec = InModuleScope PurviewPostureAnalyzer -Parameters @{ TmpDir = $tmp } {
                param($TmpDir)
                Mock Get-PpaSensitivityLabels { throw 'BOOM-ipps-not-connected' }
                $r = Invoke-PurviewPostureAnalyzer -OutputDirectory $TmpDir -WarningAction SilentlyContinue
                $r.Normalized.sections | Where-Object { $_.id -eq 'Sensitivity_Labels' }
            }
            $sec.findings[0].id | Should -Be 'Sensitivity_Labels-ERR'
            $sec.findings[0].status | Should -Be 'Verify manually'
            ($sec.findings[0].table.rows | Where-Object { $_.remark }).remark | Should -Match 'BOOM-ipps-not-connected'
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
