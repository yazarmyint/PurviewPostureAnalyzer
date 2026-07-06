# Coverage.Tests.ps1 - Wave 4 Part D pins: the coverage matrix (spec section 5).
# Pure projection (no reads, no findings), closed six-state cell enum with mandatory
# Partial reason codes, best-of aggregation, Unknown gating on governing collector
# outcome, provenance markers, audit strip grounded on the AuditConfig singleton,
# principal strip, N/A applicability, print-safe None-vs-Unknown, and matrix
# redaction. Wave 5 cleanup Part 1: the Copilot x Retention render-hold is LIFTED
# (the cell classifies live from the DSPM app-retention projection) and the
# auto-labeling / retention provenance upgraded to live-verified, with the
# provisional-marker legend invariant pinned both ways.
# Non-delta: must pass under PS 5.1 AND 7+. Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    foreach ($f in (Get-ChildItem -Path (Join-Path $script:RepoRoot 'Private') -Recurse -Filter '*.ps1')) { . $f.FullName }

    function Read-PpaFixtureJson([string]$RelPath) {
        [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot $RelPath), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    function New-PpaDenseRawMap {
        @{
            Sensitivity_Labels       = Read-PpaFixtureJson 'Samples\sample-raw\labels.json'
            Data_Loss_Prevention     = Read-PpaFixtureJson 'Samples\sample-raw\dlp.json'
            Retention                = Read-PpaFixtureJson 'Samples\sample-raw\retention.json'
            Insider_Risk             = Read-PpaFixtureJson 'Samples\sample-raw\insiderrisk.json'
            Audit                    = Read-PpaFixtureJson 'Samples\sample-raw\audit.json'
            eDiscovery               = Read-PpaFixtureJson 'Samples\sample-raw\ediscovery.json'
            Communication_Compliance = Read-PpaFixtureJson 'Samples\sample-raw\commscompliance.json'
            DSPM_for_AI              = Read-PpaFixtureJson 'Samples\sample-raw\dspm.json'
        }
    }
    function Get-PpaCell {
        param($Model, [string]$Row, [string]$Column)
        return @($Model.cells | Where-Object { $_.row -eq $Row -and $_.column -eq $Column })[0]
    }
    $script:DenseModel = Get-PpaCoverageModel -RawMap (New-PpaDenseRawMap)
}

Describe 'Matrix purity (6.2 #11): pure projection, no reads, no findings' {
    It 'matrix code paths contain no collector calls and no finding factories' {
        $files = @(
            Join-Path $script:RepoRoot 'Private\Analyze\Get-PpaCoverageModel.ps1'
            Join-Path $script:RepoRoot 'Private\Render\PpaCoverageMatrix.ps1'
        )
        foreach ($f in $files) {
            Test-Path -LiteralPath $f | Should -BeTrue
            $code = [System.IO.File]::ReadAllText($f) -replace '(?m)#.*$', ''
            $code | Should -Not -Match 'Invoke-PpaReadCmdlet'
            $code | Should -Not -Match 'New-PpaFinding'
            $code | Should -Not -Match 'New-PpaSection'
        }
    }
    It 'the CoverageModel carries no findings and no severities' {
        $script:DenseModel.PSObject.Properties.Name | Should -Not -Contain 'findings'
        foreach ($c in @($script:DenseModel.cells)) {
            $c.PSObject.Properties.Name | Should -Not -Contain 'severity'
        }
    }
}

Describe 'Cell classification against the dense fixture (6.2 #12)' {
    It 'covers the full 7x3 grid' {
        @($script:DenseModel.cells).Count | Should -Be 21
    }
    It 'Exchange x DLP is Covered (enforcing policy, full location, no exceptions)' {
        (Get-PpaCell $script:DenseModel 'exchange' 'dlp').state | Should -Be 'Covered'
    }
    It 'SharePoint x DLP is Partial carrying HasExceptions + ScopedInclude + RuleDisabled' {
        $c = Get-PpaCell $script:DenseModel 'sharePoint' 'dlp'
        $c.state | Should -Be 'Partial'
        @($c.reasons) | Should -Contain 'HasExceptions'
        @($c.reasons) | Should -Contain 'ScopedInclude'
        @($c.reasons) | Should -Contain 'RuleDisabled'
    }
    It 'OneDrive x DLP is Partial with ScopedInclude only' {
        $c = Get-PpaCell $script:DenseModel 'oneDrive' 'dlp'
        $c.state | Should -Be 'Partial'
        @($c.reasons) | Should -Be @('ScopedInclude')
    }
    It 'Power BI x DLP is Test-only (the ONLY coverage is a simulation-mode policy)' {
        (Get-PpaCell $script:DenseModel 'powerBI' 'dlp').state | Should -Be 'Test-only'
    }
    It 'Teams x DLP and Endpoint x DLP are None (matching the DLP-02/DLP-03 findings story)' {
        (Get-PpaCell $script:DenseModel 'teams' 'dlp').state | Should -Be 'None'
        (Get-PpaCell $script:DenseModel 'endpoint' 'dlp').state | Should -Be 'None'
    }
    It 'Copilot x DLP is Unknown - governing DSPM collector outcome is AccessDenied' {
        $c = Get-PpaCell $script:DenseModel 'copilot' 'dlp'
        $c.state | Should -Be 'Unknown'
    }
    It 'every Partial cell carries at least one reason code (mandatory)' {
        foreach ($c in @($script:DenseModel.cells | Where-Object { $_.state -eq 'Partial' })) {
            @($c.reasons).Count | Should -BeGreaterThan 0
        }
    }
    It 'auto-labeling cells are Test-only for EXO/SPO/OneDrive (sim-mode policy)' {
        foreach ($r in @('exchange', 'sharePoint', 'oneDrive')) {
            (Get-PpaCell $script:DenseModel $r 'autoLabel').state | Should -Be 'Test-only'
        }
    }
    It 'retention: EXO Covered; SPO Partial with SubsetOfLocations + AdaptiveScope; OneDrive/Teams None' {
        (Get-PpaCell $script:DenseModel 'exchange' 'retention').state | Should -Be 'Covered'
        $c = Get-PpaCell $script:DenseModel 'sharePoint' 'retention'
        $c.state | Should -Be 'Partial'
        @($c.reasons) | Should -Contain 'SubsetOfLocations'
        @($c.reasons) | Should -Contain 'AdaptiveScope'
        (Get-PpaCell $script:DenseModel 'oneDrive' 'retention').state | Should -Be 'None'
        (Get-PpaCell $script:DenseModel 'teams' 'retention').state | Should -Be 'None'
    }
    It 'N/A cells come from the applicability table (six of them)' {
        $na = @($script:DenseModel.cells | Where-Object { $_.state -eq 'N/A' })
        $na.Count | Should -Be 6
        (Get-PpaCell $script:DenseModel 'teams' 'autoLabel').state | Should -Be 'N/A'
        (Get-PpaCell $script:DenseModel 'endpoint' 'retention').state | Should -Be 'N/A'
        foreach ($c in $na) { $c.naReason | Should -Not -BeNullOrEmpty }
    }
    It 'Copilot x Retention is in the state enum (un-held): dense reads Unknown off the degraded DSPM collector, anchored to AI-05' {
        $c = Get-PpaCell $script:DenseModel 'copilot' 'retention'
        $c.state | Should -Be 'Unknown'
        $c.checkId | Should -Be 'AI-05'
    }
    It 'Unknown is NEVER counted in the gap total; None cells are' {
        # Dense None cells: teams/dlp, endpoint/dlp, oneDrive/retention, teams/retention.
        # Dense Unknown cells: copilot/dlp AND copilot/retention (both governed by the
        # degraded DSPM collector since the un-hold).
        $script:DenseModel.totals.gaps | Should -Be 4
        $script:DenseModel.totals.unknown | Should -Be 2
    }
    It 'raises the degraded-collector banner (DSPM outcome AccessDenied governs Copilot x DLP)' {
        $script:DenseModel.banner.show | Should -BeTrue
        @($script:DenseModel.banner.degraded | Where-Object { $_.collector -eq 'DSPM_for_AI' }).Count | Should -Be 1
    }
}

Describe 'Aggregation precedence with multiple policies per cell (6.2 #13)' {
    BeforeAll {
        function New-PpaDlpOnlyRawMap {
            param($Policies, $Rules = @())
            @{
                Data_Loss_Prevention = [pscustomobject]@{
                    outcome  = 'Populated'
                    policies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @($Policies) }
                    rules    = [pscustomobject]@{ status = 'Ok'; error = $null; items = @($Rules) }
                }
            }
        }
        function New-PpaDlpPolicy {
            param([string]$Name, [string]$Mode, [string]$ExScope, [bool]$ExException = $false)
            [pscustomobject]@{
                name = $Name; guid = "guid-$Name"; mode = $Mode
                locations = [pscustomobject]@{ exchange = ($ExScope -ne 'None'); sharePoint = $false; oneDrive = $false; teams = $false; endpoint = $false }
                locationScope = [pscustomobject]@{ exchange = $ExScope; sharePoint = 'None'; oneDrive = 'None'; teams = 'None'; endpoint = 'None'; powerBI = 'None' }
                locationExceptions = [pscustomobject]@{ exchange = $ExException; sharePoint = $false; oneDrive = $false; teams = $false; endpoint = $false; powerBI = $false }
                testModeSince = ''
            }
        }
    }
    It 'a clean enforcing policy lifts the cell to Covered over Partial and Test-only contributors' {
        $m = Get-PpaCoverageModel -RawMap (New-PpaDlpOnlyRawMap -Policies @(
            (New-PpaDlpPolicy 'clean' 'Enable' 'All'),
            (New-PpaDlpPolicy 'scoped' 'Enable' 'Scoped'),
            (New-PpaDlpPolicy 'sim' 'TestWithoutNotifications' 'All')))
        (Get-PpaCell $m 'exchange' 'dlp').state | Should -Be 'Covered'
    }
    It 'Partial beats Test-only; reasons come from the best tier' {
        $m = Get-PpaCoverageModel -RawMap (New-PpaDlpOnlyRawMap -Policies @(
            (New-PpaDlpPolicy 'scoped' 'Enable' 'Scoped'),
            (New-PpaDlpPolicy 'sim' 'TestWithoutNotifications' 'All')))
        $c = Get-PpaCell $m 'exchange' 'dlp'
        $c.state | Should -Be 'Partial'
        @($c.reasons) | Should -Be @('ScopedInclude')
    }
    It 'any enforcing policy lifts the cell above Test-only per precedence' {
        $m = Get-PpaCoverageModel -RawMap (New-PpaDlpOnlyRawMap -Policies @(
            (New-PpaDlpPolicy 'sim' 'TestWithoutNotifications' 'All')))
        (Get-PpaCell $m 'exchange' 'dlp').state | Should -Be 'Test-only'
        $m2 = Get-PpaCoverageModel -RawMap (New-PpaDlpOnlyRawMap -Policies @(
            (New-PpaDlpPolicy 'sim' 'TestWithoutNotifications' 'All'),
            (New-PpaDlpPolicy 'exc' 'Enable' 'All' $true)))
        $c2 = Get-PpaCell $m2 'exchange' 'dlp'
        $c2.state | Should -Be 'Partial'
        @($c2.reasons) | Should -Be @('HasExceptions')
    }
    It 'Unknown appears iff the governing outcome is outside Populated/Empty - never otherwise' {
        $raw = (New-PpaDlpOnlyRawMap -Policies @())
        $raw.Data_Loss_Prevention.outcome = 'Empty'
        (Get-PpaCell (Get-PpaCoverageModel -RawMap $raw) 'exchange' 'dlp').state | Should -Be 'None'
        $raw.Data_Loss_Prevention.outcome = 'Partial'
        (Get-PpaCell (Get-PpaCoverageModel -RawMap $raw) 'exchange' 'dlp').state | Should -Be 'Unknown'
    }
}

Describe 'Copilot x Retention live cell (Wave 5 cleanup Part 1: un-held)' {
    BeforeAll {
        # Inline app-retention fixtures around the VERIFIED Applications token
        # (observed live: 'Users:M365Copilot' - plural 'Users:', not the doc-grounded
        # 'User:' singular). Shape mirrors Get-PpaAppRetentionItems output.
        function New-PpaAppRetRawMap {
            param($Items)
            @{
                DSPM_for_AI = [pscustomobject]@{
                    outcome         = 'Populated'
                    copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(); thirdPartyAiDlpPolicies = @() }
                    appRetention    = [pscustomobject]@{ status = 'Ok'; error = $null; items = @($Items) }
                }
            }
        }
        function New-PpaAppRetItem {
            param([string]$Name, [string[]]$Applications, [string]$Enabled = 'True')
            [pscustomobject]@{
                name = $Name; guid = "guid-$Name"; enabled = $Enabled
                hasApplications = $true; applications = @($Applications)
                copilotCovered  = (@(@($Applications) -match '(?i)M365Copilot').Count -gt 0)
            }
        }
    }
    It 'reads Covered when a policy carries the Users:M365Copilot Applications token, and joins the totals' {
        $m = Get-PpaCoverageModel -RawMap (New-PpaAppRetRawMap @(New-PpaAppRetItem 'AI retention' @('Users:M365Copilot')))
        $c = Get-PpaCell $m 'copilot' 'retention'
        $c.state | Should -Be 'Covered'
        @($c.contributors) | Should -Contain 'AI retention'
        $c.checkId | Should -Be 'AI-05'
        $m.totals.covered | Should -Be 1
    }
    It 'reads None when app-retention policies exist but none carries the Copilot token' {
        $m = Get-PpaCoverageModel -RawMap (New-PpaAppRetRawMap @(New-PpaAppRetItem 'Teams app retention' @('Group:Teams')))
        (Get-PpaCell $m 'copilot' 'retention').state | Should -Be 'None'
    }
    It 'reads None when the app-retention read is clean but empty, and the None IS gap-counted' {
        $m = Get-PpaCoverageModel -RawMap (New-PpaAppRetRawMap @())
        (Get-PpaCell $m 'copilot' 'retention').state | Should -Be 'None'
        # Gaps for this map: copilot/dlp (no Copilot DLP policies) + copilot/retention.
        $m.totals.gaps | Should -Be 2
    }
    It 'a disabled policy carrying the token still reads Covered - the cell mirrors the AI-05 verdict, which reports coverage with the Enabled state visible in its drill-down' {
        $m = Get-PpaCoverageModel -RawMap (New-PpaAppRetRawMap @(New-PpaAppRetItem 'AI retention off' @('Users:M365Copilot') 'False'))
        (Get-PpaCell $m 'copilot' 'retention').state | Should -Be 'Covered'
    }
    It 'falls back to matching the applications tokens when copilotCovered is absent (older captures)' {
        $legacy = [pscustomobject]@{ name = 'legacy shape'; guid = 'guid-legacy'; enabled = 'True'; hasApplications = $true; applications = @('Users:M365Copilot') }
        $m = Get-PpaCoverageModel -RawMap (New-PpaAppRetRawMap @($legacy))
        (Get-PpaCell $m 'copilot' 'retention').state | Should -Be 'Covered'
    }
}

Describe 'Provenance registry (spec 5.4 + Wave 5 cleanup Part 1 upgrades)' {
    It 'all three columns read live-verified after the TEST-day provenance upgrades' {
        (Get-PpaCell $script:DenseModel 'exchange' 'dlp').provenance | Should -Be 'live-verified'
        (Get-PpaCell $script:DenseModel 'exchange' 'autoLabel').provenance | Should -Be 'live-verified'
        (Get-PpaCell $script:DenseModel 'exchange' 'retention').provenance | Should -Be 'live-verified'
    }
    It 'the shipped registry records the copilot x retention row override with the verified token grounding' {
        $reg = Get-PpaCoverageProvenance
        $reg.rowOverrides.'copilot.retention'.provenance | Should -Be 'live-verified'
        $reg.rowOverrides.'copilot.retention'.grounding | Should -Match 'Users:M365Copilot'
    }
    It 'a rowOverrides entry beats the column provenance for its cell only' {
        Mock Get-PpaCoverageProvenance {
            [pscustomobject]@{
                columns = [pscustomobject]@{
                    dlp       = [pscustomobject]@{ provenance = 'live-verified' }
                    autoLabel = [pscustomobject]@{ provenance = 'live-verified' }
                    retention = [pscustomobject]@{ provenance = 'documented-only' }
                }
                rowOverrides = [pscustomobject]@{ 'copilot.retention' = [pscustomobject]@{ provenance = 'live-verified' } }
            }
        }
        $m = Get-PpaCoverageModel -RawMap (New-PpaDenseRawMap)
        (Get-PpaCell $m 'copilot' 'retention').provenance | Should -Be 'live-verified'
        (Get-PpaCell $m 'exchange' 'retention').provenance | Should -Be 'documented-only'
    }
}

Describe 'Audit strip grounds on the AuditConfig singleton (Part A addendum)' {
    It 'dense: unified audit On' {
        $script:DenseModel.auditStrip.state | Should -Be 'On'
    }
    It 'a Partial collector outcome does NOT make the strip Unknown when the flag was read' {
        $raw = New-PpaDenseRawMap
        $raw.Audit = [pscustomobject]@{ outcome = 'Partial'; status = 'Ok'; error = $null; unifiedAuditEnabled = $true; orgStatus = 'AccessDenied' }
        (Get-PpaCoverageModel -RawMap $raw).auditStrip.state | Should -Be 'On'
    }
    It 'reads Not observed when the flag itself was not readable' {
        $raw = New-PpaDenseRawMap
        $raw.Audit = [pscustomobject]@{ outcome = 'AccessDenied'; status = 'AccessDenied'; error = 'denied'; unifiedAuditEnabled = $null; orgStatus = 'AccessDenied' }
        (Get-PpaCoverageModel -RawMap $raw).auditStrip.state | Should -Be 'NotObserved'
    }
}

Describe 'Principal-scoped strip (spec 5.2)' {
    It 'label publishing, IRM and CC lines carry counts and section links' {
        $p = @($script:DenseModel.principal)
        $p.Count | Should -Be 3
        $pub = @($p | Where-Object { $_.name -eq 'Label publishing' })[0]
        $pub.count | Should -Be 2
        $pub.sectionId | Should -Be 'Sensitivity_Labels'
        $irm = @($p | Where-Object { $_.name -eq 'Insider Risk' })[0]
        $irm.count | Should -BeNullOrEmpty
        $irm.note | Should -Match 'not readable'
        $cc = @($p | Where-Object { $_.name -eq 'Communication Compliance' })[0]
        $cc.count | Should -Be 0
    }
}

Describe 'Matrix render (spec 5.1/5.5/5.6/5.8)' {
    BeforeAll { $script:Html = Write-PpaCoverageMatrix -Coverage $script:DenseModel }

    It 'renders the degraded-collector banner above the matrix' {
        $script:Html | Should -Match 'covm-banner'
        $script:Html | Should -Match 'DSPM for AI'
    }
    It 'None and Unknown are print-distinct: family class + hatching + glyph + in-cell text' {
        $script:Html | Should -Match 'covm-none'
        $script:Html | Should -Match 'covm-unknown'
        $script:Html | Should -Match '>None<'
        $script:Html | Should -Match '>Unknown<'
        $css = Get-PpaSharedReportCss
        $css | Should -Match 'covm-none[^}]*repeating-linear-gradient'
        $css | Should -Match 'covm-unknown[^}]*radial-gradient'
        # And the print block preserves the patterns without relying on color.
        $css | Should -Match 'print-color-adjust'
    }
    It 'Copilot x Retention renders live (un-held): no held cell, no deferral footnote, AI-05 anchor kept' {
        $script:Html | Should -Not -Match 'covm-held'
        $script:Html | Should -Not -Match 'deferred pending live verification'
        $script:Html | Should -Match '#finding-AI-05'
    }
    It 'legend invariant: NO provisional marker or legend remains when the registry leaves no documented-only cells' {
        # The shipped registry is all live-verified after the Wave 5 Part 1 flip, so
        # neither the dagger nor the text explaining it may render anywhere.
        $script:Html | Should -Not -Match 'covm-prov'
        $script:Html | Should -Not -Match 'property shape documented but not yet verified'
    }
    It 'legend invariant: the marker and its explanatory legend render while >=1 documented-only cell remains' {
        Mock Get-PpaCoverageProvenance {
            [pscustomobject]@{
                columns = [pscustomobject]@{
                    dlp       = [pscustomobject]@{ provenance = 'live-verified' }
                    autoLabel = [pscustomobject]@{ provenance = 'live-verified' }
                    retention = [pscustomobject]@{ provenance = 'documented-only' }
                }
                rowOverrides = [pscustomobject]@{}
            }
        }
        $html = Write-PpaCoverageMatrix -Coverage (Get-PpaCoverageModel -RawMap (New-PpaDenseRawMap))
        $html | Should -Match 'covm-prov'
        $html | Should -Match 'property shape documented but not yet verified on a live tenant'
    }
    It 'renders the tenant audit strip and the principal strip with section anchors' {
        $script:Html | Should -Match 'Unified audit'
        $script:Html | Should -Match '#finding-AUD-01'
        $script:Html | Should -Match 'href="#Sensitivity_Labels"'
        $script:Html | Should -Match 'Insider Risk'
    }
    It 'carries the scope footer and the container-labeling out-of-scope note' {
        $script:Html | Should -Match 'Security &amp; Compliance PowerShell only'
        $script:Html | Should -Match 'Container labeling for SharePoint and Teams is out of scope'
    }
    It 'cell tooltips pass the shared render boundary: pseudonymized under -RedactNames (6.2 #14)' {
        # Unredacted: the SSN Guard policy name appears in a contributor tooltip.
        $script:Html | Should -Match 'SSN Guard'
        # Build the redaction state the way the main report does, from the dense
        # normalized fixture, then re-render the matrix.
        $dense = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-normalized-dense.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $norm = ConvertTo-PpaNormalized -Meta $dense.meta -Licensing $dense.licensing -Sections $dense.sections -Observations $dense.observations -Coverage $script:DenseModel
        Initialize-PpaRedaction -Normalized $norm -RedactNames
        try {
            $redacted = Write-PpaCoverageMatrix -Coverage $script:DenseModel
            $redacted | Should -Not -Match 'SSN Guard'
            # Contributor names must be harvested from the coverage model too, not
            # just drill-down tables - no tooltip name may survive (closeout fix).
            $redacted | Should -Not -Match 'Broad PII'
            $redacted | Should -Not -Match 'Financial Data'
            $redacted | Should -Not -Match 'Auto-label PHI'
            $redacted | Should -Match 'Policy-\d\d'
        }
        finally { Clear-PpaRedaction }
    }
}

Describe 'Sparse fixture: graceful absence (6.1)' {
    BeforeAll {
        $script:SparseModel = Get-PpaCoverageModel -RawMap @{
            Sensitivity_Labels   = Read-PpaFixtureJson 'Samples\sample-raw\sparse\labels-sparse.json'
            Data_Loss_Prevention = Read-PpaFixtureJson 'Samples\sample-raw\sparse\dlp-sparse.json'
            Retention            = Read-PpaFixtureJson 'Samples\sample-raw\sparse\retention-sparse.json'
        }
    }
    It 'builds and renders without the DSPM/Audit collectors present' {
        (Get-PpaCell $script:SparseModel 'copilot' 'dlp').state | Should -Be 'Unknown'
        # Un-held: with no DSPM collector the Copilot x Retention cell degrades to
        # Unknown like any cell whose governing collector did not run.
        (Get-PpaCell $script:SparseModel 'copilot' 'retention').state | Should -Be 'Unknown'
        $script:SparseModel.auditStrip.state | Should -Be 'NotObserved'
        (Write-PpaCoverageMatrix -Coverage $script:SparseModel) | Should -Match 'covm-grid'
    }
    It 'falls back to the boolean location shape when locationScope is absent (old fixtures)' {
        # dlp-sparse Lab Policy 4 has teams=true, mode Enable, no locationScope.
        (Get-PpaCell $script:SparseModel 'teams' 'dlp').state | Should -Be 'Covered'
    }
    It 'auto-labeling renders None when no auto policies exist' {
        (Get-PpaCell $script:SparseModel 'exchange' 'autoLabel').state | Should -Be 'None'
    }
}

Describe 'Canonical solution order (Wave 5 cleanup Part 5: body / summary / matrix)' {
    # ONE canonical ordered list (Get-PpaCanonicalSectionOrder) drives the report
    # body and - via first-appearance grouping in ConvertTo-PpaNormalized - the
    # Solutions Summary. The coverage matrix column axis is defined separately in
    # colDefs, so the three-way guardrail below is what keeps it from drifting.
    # Display-only: the orchestrator passes the analyze-order sections to
    # New-PpaSnapshotModel BEFORE assembly, so snapshot content never reorders.
    BeforeAll {
        $script:Canon = @(
            'Sensitivity_Labels', 'Data_Loss_Prevention', 'DSPM_for_AI', 'Retention',
            'Insider_Risk', 'Communication_Compliance', 'Audit', 'eDiscovery'
        )
        $dense = Read-PpaFixtureJson 'Samples\sample-normalized-dense.json'
        $script:NormDense = ConvertTo-PpaNormalized -Meta $dense.meta -Licensing $dense.licensing -Sections $dense.sections -Observations $dense.observations -Coverage $script:DenseModel
        # The fixture ships sections in the historical analyze order, so the sort
        # inside ConvertTo-PpaNormalized is what these tests observe.
    }
    It 'Get-PpaCanonicalSectionOrder pins the signed-off Option B sequence' {
        @(Get-PpaCanonicalSectionOrder) | Should -Be $script:Canon
    }
    It 'the report body renders in canonical order (DSPM for AI up to third)' {
        @($script:NormDense.sections.id) | Should -Be $script:Canon
    }
    It 'the Solutions Summary groups render in canonical family order' {
        @($script:NormDense.summary.groups.name) | Should -Be @(
            'Microsoft Information Protection', 'AI Security', 'Data Lifecycle & Records',
            'Insider Risk', 'Discovery & Response'
        )
    }
    It 'GUARDRAIL: flattened summary == body order == canonical list, and the matrix axis follows it' {
        $canon = @(Get-PpaCanonicalSectionOrder)
        $body = @($script:NormDense.sections.id)
        $flat = @($script:NormDense.summary.groups | ForEach-Object { $_.sections } | ForEach-Object { $_.id })
        $flat | Should -Be $body
        $body | Should -Be $canon
        # Matrix solution axis: each column carries its owning section; the column
        # sequence must equal the canonical list filtered to those sections.
        $colSections = @($script:DenseModel.columns | ForEach-Object { [string]$_.section })
        $colSections | Should -Be @($canon | Where-Object { $colSections -contains $_ })
    }
    It 'the matrix column axis reads Auto-labeling, DLP, Retention (canonical projection)' {
        @($script:DenseModel.columns.key)   | Should -Be @('autoLabel', 'dlp', 'retention')
        @($script:DenseModel.columns.label) | Should -Be @('Auto-labeling', 'DLP', 'Retention')
    }
    It 'a section with an unknown id sorts after the canonical ones, arrival order kept' {
        $zz = New-PpaSection -Id 'Zz_Test' -Title 'Zz Test' -Group 'G' -GroupIcon 'fas fa-cog' `
            -Glance (New-PpaGlance -Name 'Zz') -Findings @(
                New-PpaFinding -Id 'ZZZ-99' -DomId 'f-zz-1' -Title 'Unmapped' -Status 'Informational' -Whyline 'w'
            )
        $dense = Read-PpaFixtureJson 'Samples\sample-normalized-dense.json'
        $n = ConvertTo-PpaNormalized -Meta $dense.meta -Licensing $dense.licensing -Sections (@($zz) + @($dense.sections))
        @($n.sections.id)[-1] | Should -Be 'Zz_Test'
        @($n.sections.id).Count | Should -Be 9
    }
    It 'a profile subset keeps canonical relative order' {
        $dense = Read-PpaFixtureJson 'Samples\sample-normalized-dense.json'
        $subset = @($dense.sections | Where-Object { $_.id -in @('Retention', 'DSPM_for_AI', 'Audit') })
        $n = ConvertTo-PpaNormalized -Meta $dense.meta -Licensing $dense.licensing -Sections $subset
        @($n.sections.id) | Should -Be @('DSPM_for_AI', 'Retention', 'Audit')
    }
    It 'titles are untouched by the reorder: summary and body keep their exact current strings' {
        ($script:NormDense.sections | Where-Object { $_.id -eq 'Retention' }).title | Should -Be 'Retention & Records'
        ($script:NormDense.sections | Where-Object { $_.id -eq 'DSPM_for_AI' }).title | Should -Be 'DSPM for AI - Copilot Data Security'
    }
}
