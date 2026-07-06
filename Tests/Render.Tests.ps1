# Render.Tests.ps1 - the renderer reproduces the mock's structure from the sample data.
# Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'Private\Model\PpaStatus.ps1')
    . (Join-Path $script:RepoRoot 'Private\Model\New-PpaFinding.ps1')
    . (Join-Path $script:RepoRoot 'Private\Model\ConvertTo-PpaNormalized.ps1')
    . (Join-Path $script:RepoRoot 'Private\Core\Get-PpaRemediationCatalog.ps1')
    . (Join-Path $script:RepoRoot 'Private\Render\PpaRedact.ps1')
    . (Join-Path $script:RepoRoot 'Private\Render\PpaHtml.ps1')
    . (Join-Path $script:RepoRoot 'Private\Render\Export-PpaHtmlReport.ps1')

    $raw = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-normalized.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $norm = ConvertTo-PpaNormalized -Meta $raw.meta -Licensing $raw.licensing -Sections $raw.sections -Observations $raw.observations
    $script:Html = Export-PpaHtmlReport -Normalized $norm -IsSample
}

Describe 'HTML render - structure' {
    It 'contains all 8 section anchors' {
        foreach ($id in @('Sensitivity_Labels', 'Data_Loss_Prevention', 'Retention', 'Insider_Risk', 'Audit', 'eDiscovery', 'Communication_Compliance', 'DSPM_for_AI')) {
            $script:Html | Should -Match ('id="' + $id + '"')
        }
    }
    It 'emits 20 findings (21 until DLP-04 retired, Wave 5 cleanup Part 4)' {
        ([regex]::Matches($script:Html, 'class="finding"')).Count | Should -Be 20
    }
    It 'emits 19 detail tables (IRM-02 is table-less)' {
        ([regex]::Matches($script:Html, 'table table-sm detail')).Count | Should -Be 19
    }
    It 'has one collapsible drill-down per finding, plus the collapsible Posture Summary' {
        # 20 finding drill-downs + the Posture Summary header = 21. This fixture passes no
        # coverage model, so the Coverage Matrix (the other collapsible section) is not
        # rendered; a report built with coverage adds one more (see the sample builder).
        ([regex]::Matches($script:Html, 'data-toggle="collapse"')).Count | Should -Be 21
    }
}

Describe 'HTML render - computed counts' {
    It 'shows the All-Solutions totals as 2 8 3 7 0 (assume-E5 model; DLP-04 retired Wave 5 Part 4)' {
        $row  = [regex]::Match($script:Html, '(?s)All Solutions</strong></td>\s*<td align="right">(.*?)</td>').Groups[1].Value
        $nums = ([regex]::Matches($row, 'sscount">(\d+)<') | ForEach-Object { $_.Groups[1].Value }) -join ' '
        $nums | Should -Be '2 8 3 7 0'
    }
    It 'renders NO license banner and NO Requires tags (caveats live in docs, not the report)' {
        $script:Html | Should -Not -Match 'License context'
        $script:Html | Should -Not -Match 'reqline'
        $script:Html | Should -Not -Match 'Detected licensing'
    }
    It 'renders a section-header badge for each non-zero status' {
        # Sensitivity Labels: OK 1, Improvement 1, Recommendation 1, Informational 1
        $script:Html | Should -Match 'badge badge-success">OK 1<'
        $script:Html | Should -Match 'badge badge-warning">Improvement 1<'
    }
}

Describe 'HTML render - client safety' {
    It 'produces ASCII-only output (non-ASCII escaped to numeric entities)' {
        ($script:Html.ToCharArray() | Where-Object { [int][char]$_ -gt 126 }).Count | Should -Be 0
    }
    It 'collects no content - carries the read-only footer disclaimer' {
        $script:Html | Should -Match 'no document, email or prompt content'
    }
}
