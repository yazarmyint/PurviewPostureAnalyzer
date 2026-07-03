# Model.Tests.ps1 - the finding factory, status validation, glance precedence, and the
# assemble stage (counts + summary). Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'Private\Model\PpaStatus.ps1')
    . (Join-Path $script:RepoRoot 'Private\Model\New-PpaFinding.ps1')
    . (Join-Path $script:RepoRoot 'Private\Model\ConvertTo-PpaNormalized.ps1')
}

Describe 'New-PpaFinding' {
    It 'accepts a valid status' {
        (New-PpaFinding -Id 'X-01' -DomId 'f-x-1' -Title 'T' -Status 'OK').status | Should -Be 'OK'
    }
    It 'rejects an invalid status' {
        { New-PpaFinding -Id 'X-01' -DomId 'f-x-1' -Title 'T' -Status 'Gap' } | Should -Throw
    }
    It 'defaults table to null and learnmore to empty' {
        $f = New-PpaFinding -Id 'X-01' -DomId 'f-x-1' -Title 'T' -Status 'Informational'
        $f.table | Should -BeNullOrEmpty
        @($f.learnmore).Count | Should -Be 0
    }
}

Describe 'New-PpaRow / New-PpaTable' {
    It 'rejects an invalid row status' {
        { New-PpaRow -Cells @('a') -Status 'Nope' } | Should -Throw
    }
    It 'carries a remark and indent flag' {
        $r = New-PpaRow -Cells @('a', 'b') -Status 'Improvement' -Remark 'note' -Indent
        $r.remark | Should -Be 'note'
        $r.indent | Should -BeTrue
    }
    It 'builds a table with columns and rows' {
        $t = New-PpaTable -Columns @('A', 'Status') -Rows @((New-PpaRow -Cells @('x') -Status 'OK'))
        @($t.columns).Count | Should -Be 2
        @($t.rows).Count | Should -Be 1
    }
}

Describe 'Get-PpaGlanceHeadline precedence' {
    It 'Improvement beats Recommendation and OK' {
        $sec = [pscustomobject]@{ findings = @(
            [pscustomobject]@{ status = 'OK' },
            [pscustomobject]@{ status = 'Recommendation' },
            [pscustomobject]@{ status = 'Improvement' },
            [pscustomobject]@{ status = 'Informational' }) }
        Get-PpaGlanceHeadline $sec | Should -Be 'Improvement'
    }
    It 'Recommendation beats OK' {
        $sec = [pscustomobject]@{ findings = @(
            [pscustomobject]@{ status = 'OK' },
            [pscustomobject]@{ status = 'Recommendation' }) }
        Get-PpaGlanceHeadline $sec | Should -Be 'Recommendation'
    }
    It 'falls to Informational when only Informational / Verify present' {
        $sec = [pscustomobject]@{ findings = @(
            [pscustomobject]@{ status = 'Informational' },
            [pscustomobject]@{ status = 'Verify manually' }) }
        Get-PpaGlanceHeadline $sec | Should -Be 'Informational'
    }
}

Describe 'ConvertTo-PpaNormalized' {
    BeforeAll {
        $raw = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-normalized.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $script:Norm = ConvertTo-PpaNormalized -Meta $raw.meta -Licensing $raw.licensing -Sections $raw.sections -Observations $raw.observations
    }
    It 'computes the All-Solutions totals (2/8/3/7/1, assume-E5 model)' {
        $script:Norm.summary.totals.OK              | Should -Be 2
        $script:Norm.summary.totals.Improvement     | Should -Be 8
        $script:Norm.summary.totals.Recommendation  | Should -Be 3
        $script:Norm.summary.totals.Informational   | Should -Be 7
        $script:Norm.summary.totals.'Verify manually' | Should -Be 1
    }
    It 'preserves an explicit glance override (Audit stays OK despite a Verify finding)' {
        ($script:Norm.sections | Where-Object { $_.id -eq 'Audit' }).glance.status | Should -Be 'OK'
    }
    It 'groups Communication Compliance under Insider Risk' {
        $g = $script:Norm.summary.groups | Where-Object { $_.name -eq 'Insider Risk' }
        ($g.sections.title) | Should -Contain 'Communication Compliance'
    }
    It 'keeps all 21 findings' {
        (@($script:Norm.sections) | ForEach-Object { @($_.findings).Count } | Measure-Object -Sum).Sum | Should -Be 21
    }
}
