# Render.Polish.Tests.ps1 - Wave 3 report polish: fixtures, exec summary, filters,
# print, anchors, run profile, redaction, remediation. Renders each fixture variant
# once in the top-level BeforeAll and asserts against the produced HTML.
# Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    foreach ($file in (Get-ChildItem -Path (Join-Path $script:RepoRoot 'Private') -Recurse -Filter '*.ps1')) { . $file.FullName }

    function Read-PpaFixture([string]$RelPath) {
        [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot $RelPath), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }

    # Count finding cards per status straight from the normalized object - the body
    # source of truth every summary/count feature must agree with.
    function Get-PpaBodyStatusCounts($Normalized) {
        $c = [ordered]@{ 'OK'=0; 'Improvement'=0; 'Recommendation'=0; 'Informational'=0; 'Verify manually'=0 }
        foreach ($sec in @($Normalized.sections)) {
            foreach ($f in @($sec.findings)) { $c[[string]$f.status] = [int]$c[[string]$f.status] + 1 }
        }
        return $c
    }

    # Standard fixture (Northwind Health, 21 findings).
    $std = Read-PpaFixture 'Samples\sample-normalized.json'
    $script:StdNorm = ConvertTo-PpaNormalized -Meta $std.meta -Licensing $std.licensing -Sections $std.sections -Observations $std.observations
    $script:StdHtml = Export-PpaHtmlReport -Normalized $script:StdNorm -IsSample

    # Dense fixture (Contoso Pharmaceuticals, 26 findings, every severity).
    $dense = Read-PpaFixture 'Samples\sample-normalized-dense.json'
    $script:DenseNorm = ConvertTo-PpaNormalized -Meta $dense.meta -Licensing $dense.licensing -Sections $dense.sections -Observations $dense.observations
    $script:DenseHtml = Export-PpaHtmlReport -Normalized $script:DenseNorm -IsSample

    # Sparse fixture (raw sparse JSON through the real analyzers - graceful absence).
    $licMap = Get-PpaLicenseRequirements -Path (Join-Path $script:RepoRoot 'Data\license-requirements.json')
    $sparseSections = @(
        Invoke-PpaLabelAnalyzer -Raw (Read-PpaFixture 'Samples\sample-raw\sparse\labels-sparse.json') -AsOf ([datetime]'2026-07-01')
        Invoke-PpaDlpAnalyzer -Raw (Read-PpaFixture 'Samples\sample-raw\sparse\dlp-sparse.json') -AsOf ([datetime]'2026-07-01') -LicenseMap $licMap
        Invoke-PpaRetentionAnalyzer -Raw (Read-PpaFixture 'Samples\sample-raw\sparse\retention-sparse.json')
    )
    $sparseMeta = [pscustomobject]@{
        reportTitle = 'Configuration Analyzer for Microsoft Purview'; version = '2.0'; versionDate = 'June 2026'
        dateDisplay = '01-Jul-2026 10:15 UTC'; organization = 'Fabrikam Robotics (sparse fixture)'
        tenant = 'fabrikamrobotics.onmicrosoft.com'; operator = 'taylor.ng@fabrikamrobotics.com (Compliance Reader)'
        mode = 'Read-only - configuration metadata only'
    }
    $script:SparseNorm = ConvertTo-PpaNormalized -Meta $sparseMeta -Licensing ([pscustomobject]@{ note = 'n' }) -Sections $sparseSections
    $script:SparseHtml = Export-PpaHtmlReport -Normalized $script:SparseNorm

    $script:AllVariants = @(
        @{ Name = 'standard'; Html = $script:StdHtml }
        @{ Name = 'dense';    Html = $script:DenseHtml }
        @{ Name = 'sparse';   Html = $script:SparseHtml }
    )
}

Describe 'Dense fixture - shape for Wave 3 regression cases' {
    It 'renders all 8 sections and 26 findings' {
        foreach ($id in @('Sensitivity_Labels', 'Data_Loss_Prevention', 'Retention', 'Insider_Risk', 'Audit', 'eDiscovery', 'Communication_Compliance', 'DSPM_for_AI')) {
            $script:DenseHtml | Should -Match ('id="' + $id + '"')
        }
        ([regex]::Matches($script:DenseHtml, 'class="finding"')).Count | Should -Be 26
    }
    It 'uses every one of the five statuses at finding level' {
        $counts = Get-PpaBodyStatusCounts $script:DenseNorm
        foreach ($st in (Get-PpaStatusOrder)) { [int]$counts[$st] | Should -BeGreaterThan 0 }
    }
    It 'carries more than 15 Recommendation+Improvement findings (exec-summary cap case)' {
        $counts = Get-PpaBodyStatusCounts $script:DenseNorm
        ([int]$counts['Recommendation'] + [int]$counts['Improvement']) | Should -BeGreaterThan 15
    }
    It 'plants the redaction targets: a UPN, an onmicrosoft.com domain, a custom tenant domain, and policy names' {
        $raw = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-normalized-dense.json'))
        $raw | Should -Match 'leigh\.santos@contosopharma\.com'
        $raw | Should -Match 'contosopharma\.onmicrosoft\.com'
        $raw | Should -Match 'svc-dlptest@contosopharma\.onmicrosoft\.com'
        $raw | Should -Match 'Broad PII Pilot'
    }
}

Describe 'P4 - per-finding anchors' {
    It 'gives every finding card an id derived from its check ID (<Name>)' -ForEach @(
        @{ Name = 'standard' }, @{ Name = 'dense' }, @{ Name = 'sparse' }
    ) {
        $v = $script:AllVariants | Where-Object { $_.Name -eq $Name }
        ([regex]::Matches($v.Html, '<div class="finding" id="finding-')).Count |
            Should -Be ([regex]::Matches($v.Html, 'class="finding"')).Count
    }
    It 'anchors carry the literal check ID (dense spot checks)' {
        $script:DenseHtml | Should -Match 'id="finding-AI-02"'
        $script:DenseHtml | Should -Match 'id="finding-LABELS-03"'
        $script:DenseHtml | Should -Match 'id="finding-CC-01"'
    }
    It 'all id attributes are unique across the rendered report (<Name>)' -ForEach @(
        @{ Name = 'standard' }, @{ Name = 'dense' }, @{ Name = 'sparse' }
    ) {
        $v = $script:AllVariants | Where-Object { $_.Name -eq $Name }
        $ids = [regex]::Matches($v.Html, ' id="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
        $dupes = $ids | Group-Object | Where-Object { $_.Count -gt 1 }
        ($dupes | ForEach-Object { $_.Name }) -join ', ' | Should -BeNullOrEmpty
        @($ids).Count | Should -BeGreaterThan 0
    }
    It 'renders one copy-link affordance per finding (dense)' {
        ([regex]::Matches($script:DenseHtml, 'class="anchor-link"')).Count |
            Should -Be ([regex]::Matches($script:DenseHtml, 'class="finding"')).Count
    }
}

Describe 'Every fixture variant - client safety invariants' {
    It 'produces ASCII-only output for <Name>' -ForEach @(
        @{ Name = 'standard' }, @{ Name = 'dense' }, @{ Name = 'sparse' }
    ) {
        $html = ($script:AllVariants | Where-Object { $_.Name -eq $Name }).Html
        ($html.ToCharArray() | Where-Object { [int][char]$_ -gt 126 }).Count | Should -Be 0
    }
    It 'carries the read-only footer disclaimer for <Name>' -ForEach @(
        @{ Name = 'standard' }, @{ Name = 'dense' }, @{ Name = 'sparse' }
    ) {
        $html = ($script:AllVariants | Where-Object { $_.Name -eq $Name }).Html
        $html | Should -Match 'no document, email or prompt content'
    }
}
