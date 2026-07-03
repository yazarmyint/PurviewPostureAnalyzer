# Analyzer.Labels.Tests.ps1 - the Sensitivity Labels analyzer reproduces the catalog
# logic from a raw fixture (no tenant). Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'Private\Model\PpaStatus.ps1')
    . (Join-Path $script:RepoRoot 'Private\Model\New-PpaFinding.ps1')
    . (Join-Path $script:RepoRoot 'Private\Model\New-PpaSection.ps1')
    . (Join-Path $script:RepoRoot 'Private\Core\Get-PpaLicenseRequirements.ps1')
    . (Join-Path $script:RepoRoot 'Private\Analyze\Invoke-PpaLabelAnalyzer.ps1')

    $script:Raw = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-raw\labels.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    # Pin AsOf to the sample report date so the simulation-age remark is deterministic.
    $script:Sec = Invoke-PpaLabelAnalyzer -Raw $script:Raw -AsOf ([datetime]'2026-06-24')
    $script:F = @{}
    foreach ($f in $script:Sec.findings) { $script:F[$f.id] = $f }
}

Describe 'Sensitivity Labels analyzer - shape' {
    It 'produces four findings LABELS-01..04 in order' {
        @($script:Sec.findings.id) | Should -Be @('LABELS-01', 'LABELS-02', 'LABELS-03', 'LABELS-04')
    }
    It 'is the Sensitivity_Labels section under Microsoft Information Protection' {
        $script:Sec.id | Should -Be 'Sensitivity_Labels'
        $script:Sec.group | Should -Be 'Microsoft Information Protection'
    }
}

Describe 'LABELS-01 taxonomy' {
    It 'is Informational when labels exist' { $script:F['LABELS-01'].status | Should -Be 'Informational' }
    It 'lists all six labels with two indented sub-labels' {
        @($script:F['LABELS-01'].table.rows).Count | Should -Be 6
        @($script:F['LABELS-01'].table.rows | Where-Object { $_.indent }).Count | Should -Be 2
    }
    It 'renders a sub-label as parent \ child and maps scope tokens to display' {
        $legal = $script:F['LABELS-01'].table.rows | Where-Object { $_.cells[0] -like '*Legal*' }
        $legal.cells[0] | Should -Be 'Highly Confidential \ Legal'
        ($script:F['LABELS-01'].table.rows | Where-Object { $_.cells[0] -eq 'Public' }).cells[2] | Should -Be 'Files, Emails'
    }
}

Describe 'LABELS-02 published' {
    It 'is OK when an enabled policy publishes labels to users' { $script:F['LABELS-02'].status | Should -Be 'OK' }
    It 'lists each label policy with its assignment' {
        @($script:F['LABELS-02'].table.rows).Count | Should -Be 2
        ($script:F['LABELS-02'].table.rows | Where-Object { $_.cells[0] -like 'Executive*' }).cells[2] | Should -Be 'Executives (grp)'
    }
}

Describe 'LABELS-03 auto-labeling' {
    It 'is Improvement when a policy is in simulation' { $script:F['LABELS-03'].status | Should -Be 'Improvement' }
    It 'titles the finding as not enforcing' { $script:F['LABELS-03'].title | Should -Be 'Auto-labeling is not enforcing' }
    It 'shows Simulation mode and a dated remark with the computed age' {
        $row = $script:F['LABELS-03'].table.rows[0]
        $row.cells[2] | Should -Be 'Simulation'
        $row.remark | Should -Match 'since 08-Apr-2026 \(77 days\)'
        $row.remark | Should -Match '2,140 items'
    }
}

Describe 'LABELS-04 containers' {
    It 'is a Recommendation when no container-scoped labels exist' { $script:F['LABELS-04'].status | Should -Be 'Recommendation' }
    It 'reports coverage from collected container inventory' {
        ($script:F['LABELS-04'].table.rows | Where-Object { $_.cells[0] -like '*Groups*' }).cells[1] | Should -Be '0 of 143 labeled'
        ($script:F['LABELS-04'].table.rows | Where-Object { $_.cells[0] -like 'SharePoint*' }).cells[1] | Should -Be '0 of 168 labeled'
    }
}

Describe 'LABELS-04 without container inventory (v1 live default)' {
    It 'shows Verify manually coverage rows but stays a Recommendation' {
        $raw2 = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-raw\labels.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $raw2.containers = [pscustomobject]@{ status = 'NotCollected'; groups = $null; sites = $null }
        $sec2 = Invoke-PpaLabelAnalyzer -Raw $raw2 -AsOf ([datetime]'2026-06-24')
        $f04 = $sec2.findings | Where-Object { $_.id -eq 'LABELS-04' }
        $f04.status | Should -Be 'Recommendation'
        @($f04.table.rows | Where-Object { $_.status -eq 'Verify manually' }).Count | Should -Be 2
    }
}

Describe 'section glance' {
    It 'summarizes label + policy counts and auto-label state' {
        $script:Sec.glance.metric | Should -Be '6 labels'
        $script:Sec.glance.sub | Should -Match 'auto-label in sim'
    }
}
