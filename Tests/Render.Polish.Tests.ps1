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

Describe 'P1 - executive summary' {
    It 'tile counts equal body finding counts (<Name>)' -ForEach @(
        @{ Name = 'standard' }, @{ Name = 'dense' }, @{ Name = 'sparse' }
    ) {
        $v = $script:AllVariants | Where-Object { $_.Name -eq $Name }
        $norm = switch ($Name) { 'standard' { $script:StdNorm } 'dense' { $script:DenseNorm } 'sparse' { $script:SparseNorm } }
        $body = Get-PpaBodyStatusCounts $norm
        $tiles = [regex]::Matches($v.Html, 'es-num">(\d+)</span>') | ForEach-Object { [int]$_.Groups[1].Value }
        @($tiles).Count | Should -Be 5
        # Tile display order: Recommendation, Improvement, OK, Informational, Verify manually.
        $tiles[0] | Should -Be ([int]$body['Recommendation'])
        $tiles[1] | Should -Be ([int]$body['Improvement'])
        $tiles[2] | Should -Be ([int]$body['OK'])
        $tiles[3] | Should -Be ([int]$body['Informational'])
        $tiles[4] | Should -Be ([int]$body['Verify manually'])
    }
    It 'renders the run metadata line with version, timestamp and tenant hint' {
        $script:DenseHtml | Should -Match 'es-meta[^<]*Configuration Analyzer for Microsoft Purview v2\.0'
        $script:DenseHtml | Should -Match '01-Jul-2026 09:30 UTC'
        $script:DenseHtml | Should -Match 'tenant: contosopharma\.onmicrosoft\.com'
    }
    It 'caps the top-findings list at 15 with a "+N more below" line (dense: 16 -> 15 + 1)' {
        ([regex]::Matches($script:DenseHtml, 'class="es-item"')).Count | Should -Be 15
        $script:DenseHtml | Should -Match '\+1 more below'
    }
    It 'does not cap when at or under 15 (standard: 11 entries, no more-line)' {
        ([regex]::Matches($script:StdHtml, 'class="es-item"')).Count | Should -Be 11
        $script:StdHtml | Should -Not -Match 'more below'
    }
    It 'lists every Recommendation before any Improvement' {
        $sevs = [regex]::Matches($script:DenseHtml, 'data-sev="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
        $firstImpr = [array]::IndexOf($sevs, 'Improvement')
        $lastRec   = [array]::LastIndexOf($sevs, 'Recommendation')
        $lastRec | Should -BeLessThan $firstImpr
    }
    It 'every top-findings link resolves to a finding anchor in the same document (<Name>)' -ForEach @(
        @{ Name = 'standard' }, @{ Name = 'dense' }, @{ Name = 'sparse' }
    ) {
        $v = $script:AllVariants | Where-Object { $_.Name -eq $Name }
        $hrefs = [regex]::Matches($v.Html, 'class="es-item"[^>]*href="#([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
        foreach ($h in $hrefs) { $v.Html | Should -Match (' id="' + [regex]::Escape($h) + '"') }
    }
    It 'renders before the first section card and after the title card' {
        $script:DenseHtml.IndexOf('id="Execsummary"') | Should -BeLessThan $script:DenseHtml.IndexOf('id="Solutionsummary"')
        $script:DenseHtml.IndexOf('id="Execsummary"') | Should -BeLessThan $script:DenseHtml.IndexOf('id="Sensitivity_Labels"')
    }
}

Describe 'P2 - severity filters + text search' {
    It 'renders one filter bar with a chip per status, all active by default' {
        ([regex]::Matches($script:DenseHtml, 'id="Filterbar"')).Count | Should -Be 1
        foreach ($st in @('OK', 'Improvement', 'Recommendation', 'Informational', 'Verify manually')) {
            $script:DenseHtml | Should -Match ('class="fb-chip active" data-fb="' + $st + '"')
        }
        $script:DenseHtml | Should -Match 'class="fb-search"'
        $script:DenseHtml | Should -Match 'class="fb-reset"'
    }
    It 'stamps data-status on every finding card, matching body counts (<Name>)' -ForEach @(
        @{ Name = 'standard' }, @{ Name = 'dense' }, @{ Name = 'sparse' }
    ) {
        $v = $script:AllVariants | Where-Object { $_.Name -eq $Name }
        $norm = switch ($Name) { 'standard' { $script:StdNorm } 'dense' { $script:DenseNorm } 'sparse' { $script:SparseNorm } }
        $body = Get-PpaBodyStatusCounts $norm
        foreach ($st in @('OK', 'Improvement', 'Recommendation', 'Informational', 'Verify manually')) {
            ([regex]::Matches($v.Html, 'data-status="' + $st + '"')).Count | Should -Be ([int]$body[$st])
        }
    }
    It 'gives every section header a hidden-by-filter note placeholder (dense: 8)' {
        ([regex]::Matches($script:DenseHtml, 'class="sec-hiddennote"')).Count | Should -Be 8
        ([regex]::Matches($script:DenseHtml, 'class="card mt-3 seccard"')).Count | Should -Be 8
    }
    It 'wires the filter behavior in the inline polish script (vanilla, no dependencies)' {
        $script:DenseHtml | Should -Match 'applyFilter'
        $script:DenseHtml | Should -Match 'sec-allhidden'
        $script:DenseHtml | Should -Not -Match '\$\(''\.fb-chip''\)'
    }
}

Describe 'P3 - print / PDF stylesheet' {
    It 'ships an @media print block that expands drill-downs and hides interactive chrome' {
        $script:DenseHtml | Should -Match '@media print\{'
        $script:DenseHtml | Should -Match '\.collapse\{ display:block !important'
        $script:DenseHtml | Should -Match '\.filterbar, \.anchor-link, \.backlink'
    }
    It 'keeps the exec summary as page one and starts each section cleanly' {
        $script:DenseHtml | Should -Match '\.execsum\{ break-after:page'
        $script:DenseHtml | Should -Match '\.seccard\{ break-before:page'
        $script:DenseHtml | Should -Match '\.finding, \.glance \.cell, \.bd-callout\{ break-inside:avoid'
    }
    It 'preserves severity colors with print-color-adjust:exact' {
        $script:DenseHtml | Should -Match 'print-color-adjust:exact'
    }
    It 'expands drill-downs via beforeprint and restores them via afterprint' {
        $script:DenseHtml | Should -Match "addEventListener\('beforeprint'"
        $script:DenseHtml | Should -Match "addEventListener\('afterprint'"
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
