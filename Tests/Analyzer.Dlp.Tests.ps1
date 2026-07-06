# Analyzer.Dlp.Tests.ps1 - the DLP analyzer reproduces the catalog logic from a raw
# fixture (no tenant). Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'Private\Model\PpaStatus.ps1')
    . (Join-Path $script:RepoRoot 'Private\Model\New-PpaFinding.ps1')
    . (Join-Path $script:RepoRoot 'Private\Model\New-PpaSection.ps1')
    . (Join-Path $script:RepoRoot 'Private\Analyze\Invoke-PpaDlpAnalyzer.ps1')

    . (Join-Path $script:RepoRoot 'Private\Core\Get-PpaLicenseRequirements.ps1')
    $script:Raw = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-raw\dlp.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $script:Map = Get-PpaLicenseRequirements -Path (Join-Path $script:RepoRoot 'Data\license-requirements.json')
    $script:Sec = Invoke-PpaDlpAnalyzer -Raw $script:Raw -AsOf ([datetime]'2026-06-24') -LicenseMap $script:Map
    $script:F = @{}
    foreach ($f in $script:Sec.findings) { $script:F[$f.id] = $f }
}

Describe 'DLP analyzer - shape' {
    It 'produces three findings DLP-01..03 (DLP-04 retired, Wave 5 cleanup Part 4)' {
        @($script:Sec.findings.id) | Should -Be @('DLP-01', 'DLP-02', 'DLP-03')
    }
}

Describe 'DLP-01 policies' {
    It 'is Informational inventory with a counted title' {
        $script:F['DLP-01'].status | Should -Be 'Informational'
        $script:F['DLP-01'].title | Should -Be '6 DLP policies exist (4 enforcing, 2 in test)'
    }
    It 'marks enforcing policies OK and test-mode policies Improvement' {
        @($script:F['DLP-01'].table.rows | Where-Object { $_.status -eq 'OK' }).Count | Should -Be 4
        @($script:F['DLP-01'].table.rows | Where-Object { $_.status -eq 'Improvement' }).Count | Should -Be 2
    }
    It 'shows a dated test-mode remark on the Broad PII policy' {
        $broad = $script:F['DLP-01'].table.rows | Where-Object { $_.cells[0] -like 'Broad PII*' }
        $broad.remark | Should -Match 'in test mode since 12-May-2026'
    }
    It 'summarizes disabled rules on the Legacy policy' {
        $legacy = $script:F['DLP-01'].table.rows | Where-Object { $_.cells[0] -eq 'Legacy DLP' }
        $legacy.cells[2] | Should -Be 'Test mode; 2 of 3 rules disabled'
    }
}

Describe 'DLP-02 Teams scope' {
    It 'is Improvement when Teams is in no policy' { $script:F['DLP-02'].status | Should -Be 'Improvement' }
    It 'marks the Teams row Improvement and content locations OK' {
        ($script:F['DLP-02'].table.rows | Where-Object { $_.cells[0] -eq 'Microsoft Teams' }).status | Should -Be 'Improvement'
        ($script:F['DLP-02'].table.rows | Where-Object { $_.cells[0] -eq 'Exchange Online' }).status | Should -Be 'OK'
    }
}

Describe 'DLP-03 Endpoint DLP' {
    It 'is Improvement when no endpoint location is scoped' { $script:F['DLP-03'].status | Should -Be 'Improvement' }
    It 'reports the device-onboarded count as Verify manually (not a false 0)' {
        ($script:F['DLP-03'].table.rows | Where-Object { $_.cells[0] -eq 'Devices onboarded' }).status | Should -Be 'Verify manually'
    }
}

Describe 'DLP-04 retired (Wave 5 cleanup Part 4): the HIPAA check is gone, the section is whole' {
    # Removed with nothing in its place (ruled): the check presumed a healthcare
    # engagement, and the section already carries the industry-neutral signals
    # (enforcement mode in DLP-01 remarks, workload coverage in DLP-02, endpoint
    # posture in DLP-03). The ID is tombstoned in CHECK_CATALOG.md, never reused.
    It 'emits NO DLP-04 finding even when HIPAA-flavored policies exist in the fixture' {
        @($script:Sec.findings.id) | Should -Not -Contain 'DLP-04'
    }
    It 'emits no HIPAA-titled finding at all - neither branch of the retired check survives' {
        @($script:Sec.findings | Where-Object { $_.title -match '(?i)HIPAA' }).Count | Should -Be 0
    }
    It 'the DLP section still assembles cleanly without it: three findings, glance intact' {
        @($script:Sec.findings).Count | Should -Be 3
        $script:Sec.id | Should -Be 'Data_Loss_Prevention'
        $script:Sec.title | Should -Be 'Data Loss Prevention'
        $script:Sec.glance.metric | Should -Be '6 policies'
    }
}

Describe 'DLP-02/03 license annotations' {
    It 'annotates Teams and Endpoint DLP with their E5 requirement' {
        $script:F['DLP-02'].requires | Should -Match 'E5'
        $script:F['DLP-03'].requires | Should -Match 'E5'
    }
}

Describe 'section glance' {
    It 'summarizes policy count, enforcing count and Teams scope' {
        $script:Sec.glance.metric | Should -Be '6 policies'
        $script:Sec.glance.sub | Should -Match '4 enforcing'
        $script:Sec.glance.sub | Should -Match 'Teams unscoped'
    }
}
