# Render.Polish.Tests.ps1 - Wave 3 report polish: fixtures, posture summary, filters,
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

    # Redacted dense variants (P6). Rendered AFTER the plain variants on purpose -
    # the no-leakage test re-renders plain afterwards and compares byte-for-byte.
    $script:RedactHtml      = Export-PpaHtmlReport -Normalized $script:DenseNorm -IsSample -Redact
    $script:RedactNamesHtml = Export-PpaHtmlReport -Normalized $script:DenseNorm -IsSample -Redact -RedactNames
    $script:SparseRedactHtml = Export-PpaHtmlReport -Normalized $script:SparseNorm -Redact

    # Profile-filtered dense variant (P5): DSPM_for_AI and Audit excluded at render time.
    $script:ProfSelection = Select-PpaSections -Sections @($dense.sections) -ExcludeSection @('DSPM_for_AI', 'Audit')
    $script:ProfNorm = ConvertTo-PpaNormalized -Meta $dense.meta -Licensing $dense.licensing -Sections $script:ProfSelection.Sections -Observations $dense.observations
    $script:ProfHtml = Export-PpaHtmlReport -Normalized $script:ProfNorm -IsSample -ExcludedSections $script:ProfSelection.ExcludedTitles

    $script:AllVariants = @(
        @{ Name = 'standard'; Html = $script:StdHtml }
        @{ Name = 'dense';    Html = $script:DenseHtml }
        @{ Name = 'sparse';   Html = $script:SparseHtml }
    )
}

Describe 'Dense fixture - shape for Wave 3 regression cases' {
    It 'renders all 8 sections and 25 findings (26 until DLP-04 retired, Wave 5 Part 4)' {
        foreach ($id in @('Sensitivity_Labels', 'Data_Loss_Prevention', 'Retention', 'Insider_Risk', 'Audit', 'eDiscovery', 'Communication_Compliance', 'DSPM_for_AI')) {
            $script:DenseHtml | Should -Match ('id="' + $id + '"')
        }
        ([regex]::Matches($script:DenseHtml, 'class="finding"')).Count | Should -Be 25
    }
    It 'uses every one of the five statuses at finding level' {
        $counts = Get-PpaBodyStatusCounts $script:DenseNorm
        foreach ($st in (Get-PpaStatusOrder)) { [int]$counts[$st] | Should -BeGreaterThan 0 }
    }
    It 'carries more than 15 Recommendation+Improvement findings (posture-summary cap case)' {
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

Describe 'P1 - posture summary' {
    It 'renders the "Posture Summary" heading with no stale "Executive" copy' {
        $script:DenseHtml | Should -Match '<strong>Posture Summary</strong>'
        $script:DenseHtml | Should -Not -Match 'Executive Summary'
        $script:DenseHtml | Should -Not -Match 'Execsummary'
        $script:DenseHtml | Should -Not -Match 'execsum'
    }
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
        $script:DenseHtml.IndexOf('id="Posturesummary"') | Should -BeLessThan $script:DenseHtml.IndexOf('id="Solutionsummary"')
        $script:DenseHtml.IndexOf('id="Posturesummary"') | Should -BeLessThan $script:DenseHtml.IndexOf('id="Sensitivity_Labels"')
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
    It 'keeps the posture summary as page one and starts each section cleanly' {
        $script:DenseHtml | Should -Match '\.postsum\{ break-after:page'
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

Describe 'P5 - run profile: section include/exclude' {
    It 'omits excluded sections from the body entirely' {
        $script:ProfHtml | Should -Not -Match 'id="DSPM_for_AI"'
        $script:ProfHtml | Should -Not -Match 'id="Audit"'
        ([regex]::Matches($script:ProfHtml, 'class="card mt-3 seccard"')).Count | Should -Be 6
    }
    It 'lists the excluded sections in a single footer line' {
        $script:ProfHtml | Should -Match 'Sections excluded by run profile: Audit, DSPM for AI - Copilot Data Security'
        ([regex]::Matches($script:ProfHtml, 'profile-note')).Count | Should -Be 2  # CSS rule + the note itself
    }
    It 'renders no profile note when nothing is excluded' {
        $script:DenseHtml | Should -Not -Match 'Sections excluded by run profile'
    }
    It 'adjusts posture-summary tile counts to the included sections only' {
        $body = Get-PpaBodyStatusCounts $script:ProfNorm
        $tiles = [regex]::Matches($script:ProfHtml, 'es-num">(\d+)</span>') | ForEach-Object { [int]$_.Groups[1].Value }
        $tiles[0] | Should -Be ([int]$body['Recommendation'])
        $tiles[1] | Should -Be ([int]$body['Improvement'])
        # Dense body has 25 findings (DLP-04 retired); Audit (3) + DSPM (6) excluded -> 16 remain.
        ($tiles | Measure-Object -Sum).Sum | Should -Be 16
    }
    It 'include means "only these"' {
        $sel = Select-PpaSections -Sections $script:DenseNorm.sections -IncludeSection @('Audit', 'eDiscovery')
        @($sel.Sections).Count | Should -Be 2
        @($sel.ExcludedTitles).Count | Should -Be 6
    }
    It 'throws on an unknown section key, naming the valid keys' {
        { Select-PpaSections -Sections $script:DenseNorm.sections -ExcludeSection @('Nope_Section') } |
            Should -Throw '*Nope_Section*Sensitivity_Labels*'
    }
}

Describe 'P5 - entry-script parameter plumbing (no tenant, graceful degradation)' {
    BeforeAll {
        foreach ($p in (Get-ChildItem (Join-Path $script:RepoRoot 'Public') -Filter '*.ps1')) { . $p.FullName }
        $script:P5Out = Join-Path ([System.IO.Path]::GetTempPath()) ('ppa-p5-' + [guid]::NewGuid().ToString('N'))
    }
    AfterAll {
        if ($script:P5Out -and (Test-Path -LiteralPath $script:P5Out)) {
            Remove-Item -LiteralPath $script:P5Out -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It '-ExcludeSection removes the section and the report carries the footer note' {
        $r = Invoke-PurviewPostureAnalyzer -OutputDirectory $script:P5Out -ExcludeSection 'Audit' -WarningAction SilentlyContinue
        @($r.Normalized.sections).Count | Should -Be 7
        @($r.Normalized.sections | Where-Object { $_.id -eq 'Audit' }).Count | Should -Be 0
        [System.IO.File]::ReadAllText($r.HtmlPath) | Should -Match 'Sections excluded by run profile: Audit'
    }
    It '-Profile (psd1) expresses the same exclusions; explicit parameters override it' {
        $prof = Join-Path $TestDrive 'thin.psd1'
        Set-Content -LiteralPath $prof -Value "@{ ExcludeSection = @('Audit', 'eDiscovery') }" -Encoding Ascii
        $r = Invoke-PurviewPostureAnalyzer -OutputDirectory $script:P5Out -Profile $prof -WarningAction SilentlyContinue
        @($r.Normalized.sections).Count | Should -Be 6
        $r2 = Invoke-PurviewPostureAnalyzer -OutputDirectory $script:P5Out -Profile $prof -ExcludeSection 'Retention' -WarningAction SilentlyContinue
        @($r2.Normalized.sections).Count | Should -Be 7
        @($r2.Normalized.sections | Where-Object { $_.id -eq 'Audit' }).Count | Should -Be 1
    }
    It 'throws fast on an unknown section key (before any collection)' {
        { Invoke-PurviewPostureAnalyzer -OutputDirectory $script:P5Out -IncludeSection 'Not_A_Section' } |
            Should -Throw '*Not_A_Section*'
    }
}

Describe 'P6 - redaction mode' {
    It '-Redact masks every planted UPN and email address' {
        $script:RedactHtml | Should -Not -Match 'leigh\.santos@contosopharma\.com'
        $script:RedactHtml | Should -Not -Match 'svc-dlptest@'
        $script:RedactHtml | Should -Not -Match 'dl-exec@'
        $script:RedactHtml | Should -Match 'user\d\d@\[redacted\]'
    }
    It '-Redact masks the tenant domains (onmicrosoft + custom) everywhere, including the posture-summary tenant hint' {
        $script:RedactHtml | Should -Not -Match '(?i)contosopharma'
        $script:RedactHtml | Should -Match '\[redacted-domain-\d\d\]'
    }
    It 'uses a stable token for the same value wherever it appears (tenant hint: title card + posture summary)' {
        ([regex]::Matches($script:RedactHtml, '\[redacted-domain-01\]')).Count | Should -BeGreaterOrEqual 2
    }
    It 'leaves Microsoft Learn and portal URLs untouched' {
        $script:RedactHtml | Should -Match 'https://learn\.microsoft\.com/en-us/purview/sensitivity-labels'
        $script:RedactHtml | Should -Match 'https://purview\.microsoft\.com'
    }
    It 'shows a visible REDACTED banner naming the scope' {
        $script:RedactHtml | Should -Match 'class="redact-flag"'
        $script:RedactHtml | Should -Match 'REDACTED report'
        $script:RedactHtml | Should -Not -Match 'policy and label names pseudonymized'
        $script:RedactNamesHtml | Should -Match 'policy and label names pseudonymized'
    }
    It 'does NOT pseudonymize policy names under plain -Redact' {
        $script:RedactHtml | Should -Match 'Broad PII Pilot'
        $script:RedactHtml | Should -Match 'Contoso Global Label Policy'
    }
    It '-RedactNames pseudonymizes policy/label names consistently, including inside remarks' {
        $script:RedactNamesHtml | Should -Not -Match 'Broad PII Pilot'
        $script:RedactNamesHtml | Should -Not -Match 'Auto-label PHI and PII'
        $script:RedactNamesHtml | Should -Match 'Policy-\d\d'
        $script:RedactNamesHtml | Should -Match 'Label-\d\d'
    }
    It 'does not mask anything when the switches are absent' {
        $script:DenseHtml | Should -Match 'leigh\.santos@contosopharma\.com'
        $script:DenseHtml | Should -Match 'contosopharma\.onmicrosoft\.com'
        $script:DenseHtml | Should -Not -Match '\[redacted'
        $script:DenseHtml | Should -Not -Match 'redact-flag"'
    }
    It 'masks the sparse fixture operator UPN too (graceful with analyzer-built sections)' {
        $script:SparseRedactHtml | Should -Not -Match 'taylor\.ng@fabrikamrobotics\.com'
        $script:SparseRedactHtml | Should -Match 'user\d\d@\[redacted\]'
    }
    It 'redacted output is still pure ASCII' {
        ($script:RedactNamesHtml.ToCharArray() | Where-Object { [int][char]$_ -gt 126 }).Count | Should -Be 0
    }
    It 'is render-time only: the normalized object is untouched and later plain renders are unaffected' {
        [string]$script:DenseNorm.meta.tenant | Should -Be 'contosopharma.onmicrosoft.com'
        (Export-PpaHtmlReport -Normalized $script:DenseNorm -IsSample) | Should -Be $script:DenseHtml
    }
}

Describe 'P7 - remediation snippets' {
    It 'renders a remediation region for every Improvement/Recommendation finding with a catalog entry (dense: 16)' {
        ([regex]::Matches($script:DenseHtml, '<details class="remed">')).Count | Should -Be 16
    }
    It 'never renders remediation on OK / Informational / Verify-manually findings' {
        # These have catalog entries but must not show the region. Capture each card
        # from its anchor to the next finding card (or the section back-link).
        foreach ($id in @('LABELS-01', 'ED-01', 'AUD-03', 'LABELS-02')) {
            $card = [regex]::Match($script:DenseHtml, '(?s)id="finding-' + $id + '".*?(?=<div class="finding"|<div class="text-right backlink")').Value
            $card | Should -Not -BeNullOrEmpty
            $card | Should -Not -Match 'class="remed"'
        }
    }
    It 'renders nothing when the catalog has no entry for the check ID' {
        $sec = New-PpaSection -Id 'Zz_Test' -Title 'Zz Test' -Group 'G' -GroupIcon 'fas fa-cog' `
            -Glance (New-PpaGlance -Name 'Zz') -Findings @(
                New-PpaFinding -Id 'ZZZ-99' -DomId 'f-zz-1' -Title 'Unmapped check' -Status 'Improvement' -Whyline 'w'
            )
        $norm = ConvertTo-PpaNormalized -Meta $script:DenseNorm.meta -Licensing $script:DenseNorm.licensing -Sections @($sec)
        (Export-PpaHtmlReport -Normalized $norm) | Should -Not -Match 'class="remed"'
    }
    It 'contains no PowerShell anywhere in the rendered report (<Name>) - Wave 3.1 B1' -ForEach @(
        @{ Name = 'standard' }, @{ Name = 'dense' }, @{ Name = 'sparse' }
    ) {
        $v = $script:AllVariants | Where-Object { $_.Name -eq $Name }
        $v.Html | Should -Not -Match '<pre><code>'
        $v.Html | Should -Not -Match 'Connect-IPPSSession'
        $v.Html | Should -Not -Match 'Connect-ExchangeOnline'
        $v.Html | Should -Not -Match '\bSet-[A-Z][A-Za-z]+'
        $v.Html | Should -Not -Match 'remed-code'
        $v.Html | Should -Not -Match 'remed-copy'
    }
    It 'remediation regions render prose portal guidance plus a Learn link (LABELS-04)' {
        $card = [regex]::Match($script:DenseHtml, '(?s)id="finding-LABELS-04".*?</details>').Value
        $card | Should -Match 'remed-portal'
        $card | Should -Match 'remed-learn'
    }
    It 'the catalog file itself carries no cmdlet keys or PowerShell text' {
        $raw = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Data\remediation-catalog.json'))
        $raw | Should -Not -Match '"cmdlet"'
        $raw | Should -Not -Match '\bSet-[A-Z]'
        $raw | Should -Not -Match 'Connect-IPPSSession|Connect-ExchangeOnline'
    }
    It 'every remediation region carries the evergreen caution and a Learn link (F-011: no "draft" framing)' {
        ([regex]::Matches($script:DenseHtml, 'remed-note')).Count | Should -BeGreaterOrEqual 16
        # F-011: the "draft" tag/label is gone; the caution reads as an evergreen note.
        $script:DenseHtml | Should -Not -Match 'remed-draft-tag'
        $script:DenseHtml | Should -Match 'confirm against the current Microsoft Learn'
        $card = [regex]::Match($script:DenseHtml, '(?s)id="finding-CC-01".*?</details>').Value
        $card | Should -Match 'remed-learn'
        $card | Should -Match 'https://learn\.microsoft\.com/en-us/purview/communication-compliance'
    }
    It 'remediation regions are native details elements - they never inflate the collapse count' {
        # 25 finding drill-downs (26 until DLP-04 retired, Wave 5 Part 4) + the Posture
        # Summary header = 26. This fixture passes no coverage model, so the Coverage
        # Matrix collapsible is not rendered. Remediation <details> add none; the vanilla
        # collapse handler matches [data-target], adding none.
        ([regex]::Matches($script:DenseHtml, 'data-toggle="collapse"')).Count | Should -Be 26
    }
    It 'the catalog defines an entry for every catalog check ID referenced by the dense fixture' {
        $cat = Get-PpaRemediationCatalog
        foreach ($sec in @($script:DenseNorm.sections)) {
            foreach ($f in @($sec.findings)) {
                (Get-PpaRemediation -Catalog $cat -CheckId ([string]$f.id)) | Should -Not -BeNullOrEmpty
            }
        }
    }
    It 'every catalog entry carries a grounding field (skill/learn/established/none) - Wave 3.1 B5' {
        $cat = Get-PpaRemediationCatalog
        foreach ($prop in $cat.checks.PSObject.Properties) {
            $g = [string]$prop.Value.grounding
            $g | Should -Not -BeNullOrEmpty -Because ($prop.Name + ' must record its grounding')
            @('skill', 'learn', 'established', 'none') | Should -Contain $g
        }
    }
    It 'not-grounded entries (AI-04) carry the minimal fallback, grounded entries carry decision-naming prose' {
        $cat = Get-PpaRemediationCatalog
        [string]$cat.checks.'AI-04'.grounding | Should -Be 'none'
        # Spot-check a grounded entry names the decision, not just a blade path.
        [string]$cat.checks.'LABELS-03'.portalPath | Should -Match 'simulation'
        [string]$cat.checks.'IRM-01'.portalPath | Should -Match 'privacy'
    }
    It 'the retired DLP-04 has no live remediation catalog entry (tombstoned in CHECK_CATALOG.md only)' {
        $cat = Get-PpaRemediationCatalog
        @($cat.checks.PSObject.Properties.Name) | Should -Not -Contain 'DLP-04'
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

Describe 'Mockup A v2 port - wider layout + solution section icons' {
    It 'ports the wider responsive shell (1680px), not full-bleed' {
        $script:DenseHtml | Should -Match '\.app-body\{ max-width:1680px'
    }
    It 'caps prose measure and uses a two-column top-findings grid at width' {
        $script:DenseHtml | Should -Match 'max-width:82ch'
        $script:DenseHtml | Should -Match 'grid-template-columns:1fr 1fr'
    }
    It 'defines exactly one decorative ::before icon rule, scoped to solution section headers' {
        # Empty ::before content => screen-reader silent. Exactly one such rule exists and
        # it is .seccard-scoped, so no other element (Solutions Summary, glance) gets an icon.
        ([regex]::Matches($script:DenseHtml, 'a::before\{ content:""')).Count | Should -Be 1
        $script:DenseHtml | Should -Match '\.seccard > \.card-header \.col-sm > a::before\{ content:""'
    }
    It 'maps exactly one icon custom property per known solution section (8)' {
        ([regex]::Matches($script:DenseHtml, '--sec-icon:url\(')).Count | Should -Be 8
        foreach ($id in @('Sensitivity_Labels', 'Data_Loss_Prevention', 'Retention', 'Insider_Risk', 'Audit', 'eDiscovery', 'Communication_Compliance', 'DSPM_for_AI')) {
            $script:DenseHtml | Should -Match ('#' + $id + '\{ --sec-icon:url\(')
        }
    }
    It 'provides a neutral fallback icon for unmapped sections' {
        $script:DenseHtml | Should -Match 'background:var\(--sec-icon, url\("data:image/svg\+xml'
    }
    It 'never gives the Solutions Summary table an icon' {
        $script:DenseHtml | Should -Not -Match '#Solutionsummary\{ --sec-icon'
        $script:DenseHtml | Should -Not -Match 'ssparent[^{]*--sec-icon'
    }
    It 'adds no icon elements or icon ids (CSS-only, no body markup change)' {
        $script:DenseHtml | Should -Not -Match 'class="secicon"'
        $script:DenseHtml | Should -Not -Match 'id="secicon'
        # section anchors/ids and count are unchanged by the icon feature
        ([regex]::Matches($script:DenseHtml, 'class="card mt-3 seccard"')).Count | Should -Be 8
        foreach ($id in @('Sensitivity_Labels', 'Data_Loss_Prevention', 'Retention', 'Insider_Risk', 'Audit', 'eDiscovery', 'Communication_Compliance', 'DSPM_for_AI')) {
            $script:DenseHtml | Should -Match ('id="' + $id + '"')
        }
    }
    It 'keeps icons offline: data-uri SVG only, no external image/font/CDN' {
        $script:DenseHtml | Should -Match 'url\("data:image/svg\+xml'
        $script:DenseHtml | Should -Not -Match '(?i)<img |cdnjs|jsdelivr|googleapis|fonts\.g|font-awesome'
    }
    It 'adds the additive posture-at-a-glance band script, with no stale Executive copy' {
        $script:DenseHtml | Should -Match 'ppa-execband'
        $script:DenseHtml | Should -Match 'Posture at a glance'
        $script:DenseHtml | Should -Not -Match 'Executive Summary'
        $script:DenseHtml | Should -Not -Match 'execsum'
    }
    It 'icons and band inflate neither the collapse-toggle count nor the finding count' {
        ([regex]::Matches($script:DenseHtml, 'data-toggle="collapse"')).Count | Should -Be 26
        ([regex]::Matches($script:DenseHtml, 'class="finding"')).Count | Should -Be 25
    }
}
