# Analyzer.Retention.Tests.ps1 - the Retention analyzer reproduces the catalog logic
# from a raw fixture (no tenant). Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'Private\Model\PpaStatus.ps1')
    . (Join-Path $script:RepoRoot 'Private\Model\New-PpaFinding.ps1')
    . (Join-Path $script:RepoRoot 'Private\Model\New-PpaSection.ps1')
    . (Join-Path $script:RepoRoot 'Private\Core\Get-PpaLicenseRequirements.ps1')
    . (Join-Path $script:RepoRoot 'Private\Analyze\Invoke-PpaRetentionAnalyzer.ps1')

    $script:Raw = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-raw\retention.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $script:Sec = Invoke-PpaRetentionAnalyzer -Raw $script:Raw
    $script:F = @{}
    foreach ($f in $script:Sec.findings) { $script:F[$f.id] = $f }
}

Describe 'Retention analyzer - shape' {
    It 'produces three findings RET-01..03 under Data Lifecycle & Records' {
        @($script:Sec.findings.id) | Should -Be @('RET-01', 'RET-02', 'RET-03')
        $script:Sec.group | Should -Be 'Data Lifecycle & Records'
    }
}

Describe 'RET-01 inventory' {
    It 'is Informational with a counted title' {
        $script:F['RET-01'].status | Should -Be 'Informational'
        $script:F['RET-01'].title | Should -Be '3 retention policies, 8 retention labels'
    }
    It 'renders scope + locations in the remarks column' {
        ($script:F['RET-01'].table.rows | Where-Object { $_.cells[0] -like 'Finance*' }).cells[2] | Should -Match 'Static'
        ($script:F['RET-01'].table.rows | Where-Object { $_.cells[0] -like 'Finance*' }).cells[2] | Should -Match 'Exchange'
    }
}

Describe 'RET-02 adaptive scopes' {
    It 'is Improvement when there are zero adaptive scopes' { $script:F['RET-02'].status | Should -Be 'Improvement' }
    It 'shows static count Informational and adaptive count Improvement' {
        # Wave 4 Part D: 'General - 3yr' became adaptive in the dense fixture so the
        # matrix exercises the AdaptiveScope reason code; static count is now 2.
        ($script:F['RET-02'].table.rows | Where-Object { $_.cells[0] -eq 'Static scopes' }).cells[1] | Should -Be '2'
        ($script:F['RET-02'].table.rows | Where-Object { $_.cells[0] -eq 'Adaptive scopes' }).status | Should -Be 'Improvement'
    }
}

Describe 'RET-03 manual-apply labels' {
    It 'is Improvement when labels have no auto-apply condition' { $script:F['RET-03'].status | Should -Be 'Improvement' }
    It 'summarizes the full count in a remark' {
        ($script:F['RET-03'].table.rows | Where-Object { $_.remark }).remark | Should -Match '8 of 8 retention labels'
    }
}

Describe 'section glance' {
    It 'summarizes policies, labels and scope state' {
        $script:Sec.glance.metric | Should -Be '3 policies'
        $script:Sec.glance.sub | Should -Match 'static only'
    }
}
