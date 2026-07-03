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
    $script:SitMap = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Data\dlp-sit-tiers.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $script:Map = Get-PpaLicenseRequirements -Path (Join-Path $script:RepoRoot 'Data\license-requirements.json')
    $script:Sec = Invoke-PpaDlpAnalyzer -Raw $script:Raw -AsOf ([datetime]'2026-06-24') -LicenseMap $script:Map -SitTierMap $script:SitMap
    $script:F = @{}
    foreach ($f in $script:Sec.findings) { $script:F[$f.id] = $f }
}

Describe 'DLP analyzer - shape' {
    It 'produces four findings DLP-01..04' {
        @($script:Sec.findings.id) | Should -Be @('DLP-01', 'DLP-02', 'DLP-03', 'DLP-04')
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

Describe 'DLP-04 HIPAA template (Verify-flavored, no tenant-tier assertion)' {
    It 'is Verify manually - the tool cannot assert detectors are inactive on this tenant' {
        $script:F['DLP-04'].status | Should -Be 'Verify manually'
        $script:F['DLP-04'].title | Should -Match 'verify tenant tier'
    }
    It 'flags mapped named-entity detectors as requires-E5 / verify' {
        $icd = $script:F['DLP-04'].table.rows | Where-Object { $_.cells[0] -like '*ICD-10-CM*' }
        $icd.status | Should -Be 'Verify manually'
        $icd.cells[1] | Should -Match 'requires E5'
    }
    It 'marks an unmapped SIT tier-not-confirmed - never a silent OK' {
        ($script:F['DLP-04'].table.rows | Where-Object { $_.cells[0] -eq 'U.S. SSN' }).status | Should -Be 'Verify manually'
        @($script:F['DLP-04'].table.rows | Where-Object { $_.status -eq 'OK' }).Count | Should -Be 0
    }
    It 'records the map review date and the no-detection caveat in a remark' {
        $remark = ($script:F['DLP-04'].table.rows | Where-Object { $_.remark }).remark
        $remark | Should -Match 'last reviewed 2026-07-01'
        $remark | Should -Match 'does not read licensing'
    }
    It 'carries the Requires annotation' {
        $script:F['DLP-04'].requires | Should -Match 'E5'
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
