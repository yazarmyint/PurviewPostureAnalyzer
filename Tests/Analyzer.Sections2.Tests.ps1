# Analyzer.Sections2.Tests.ps1 - Audit, eDiscovery, Insider Risk, Comms Compliance and
# DSPM for AI analyzers: evidence-only verdicts (no license detection - decision D9) with
# static 'Requires' annotations from Data/license-requirements.json.
# Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    foreach ($m in 'PpaStatus', 'New-PpaFinding', 'New-PpaSection') { . (Join-Path $script:RepoRoot "Private\Model\$m.ps1") }
    . (Join-Path $script:RepoRoot 'Private\Core\Get-PpaLicenseRequirements.ps1')
    foreach ($a in 'Invoke-PpaAuditAnalyzer', 'Invoke-PpaEdiscoveryAnalyzer', 'Invoke-PpaInsiderRiskAnalyzer', 'Invoke-PpaCommsComplianceAnalyzer', 'Invoke-PpaDspmAiAnalyzer') {
        . (Join-Path $script:RepoRoot "Private\Analyze\$a.ps1")
    }
    # Collector-level tests (TenantSetting exclusion, Copilot DLP detection) need the
    # wrapper + collectors in scope. PpaNormalize.ps1 carries the collect-side
    # contract helpers (ISO dates, outcome enum) every collector now depends on.
    . (Join-Path $script:RepoRoot 'Private\Collect\Invoke-PpaReadCmdlet.ps1')
    . (Join-Path $script:RepoRoot 'Private\Collect\PpaNormalize.ps1')
    . (Join-Path $script:RepoRoot 'Private\Collect\Get-PpaInsiderRisk.ps1')
    . (Join-Path $script:RepoRoot 'Private\Collect\Get-PpaDspmAi.ps1')
    function RawOf($n) { [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot "Samples\sample-raw\$n.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json }
    $script:Map = Get-PpaLicenseRequirements -Path (Join-Path $script:RepoRoot 'Data\license-requirements.json')

    $script:Audit = Invoke-PpaAuditAnalyzer            -Raw (RawOf 'audit')           -LicenseMap $script:Map
    $script:ED    = Invoke-PpaEdiscoveryAnalyzer       -Raw (RawOf 'ediscovery')      -LicenseMap $script:Map
    $script:IRM   = Invoke-PpaInsiderRiskAnalyzer      -Raw (RawOf 'insiderrisk')     -LicenseMap $script:Map
    $script:CC    = Invoke-PpaCommsComplianceAnalyzer  -Raw (RawOf 'commscompliance') -LicenseMap $script:Map
    $script:DSPM  = Invoke-PpaDspmAiAnalyzer           -Raw (RawOf 'dspm')            -LicenseMap $script:Map -HasSiteLabels:$false

    function Statuses($sec) { $h = @{}; foreach ($f in $sec.findings) { $h[$f.id] = $f.status }; return $h }
    function FindingOf($sec, $id) { return ($sec.findings | Where-Object { $_.id -eq $id }) }
}

Describe 'License requirements map' {
    It 'is dated and sourced from the Purview service description' {
        $script:Map.lastReviewed | Should -Match '^\d{4}-\d{2}-\d{2}$'
        $script:Map.source | Should -Match 'microsoft-purview-service-description'
    }
    It 'returns null for unannotated (E3-baseline) checks' {
        Get-PpaRequirement $script:Map 'LABELS-01' | Should -BeNullOrEmpty
    }
}

Describe 'Audit (evidence-only)' {
    It 'AUD-01 OK from evidence, AUD-03 Informational; no ingestion finding (docs-only caveat)' {
        $s = Statuses $script:Audit
        $s['AUD-01'] | Should -Be 'OK'
        $s['AUD-03'] | Should -Be 'Informational'
        $s.ContainsKey('AUD-02') | Should -BeFalse
        @($script:Audit.findings).Count | Should -Be 3
    }
    It 'AUD-03 makes no tenant-tier claim and carries a Requires annotation' {
        $f = FindingOf $script:Audit 'AUD-03'
        $f.table.rows[0].cells[1] | Should -Be 'Not assessed this session'
        $f.requires | Should -Match 'E5'
    }
    It 'glance headline is OK with metric On and no tier claim' {
        $script:Audit.glance.status | Should -Be 'OK'
        $script:Audit.glance.metric | Should -Be 'On'
        $script:Audit.glance.sub | Should -Not -Match 'Standard|Premium'
    }
    It 'AUD-04 OK from evidence with the org-default row pinned' {
        $f = FindingOf $script:Audit 'AUD-04'
        $f.status | Should -Be 'OK'
        $f.table.rows[0].cells[0] | Should -Be 'Mailbox auditing (organization default)'
        $f.table.rows[0].cells[1] | Should -Be 'On (AuditDisabled = false)'
    }
    It 'AUD-04 Improvement when the organization override disables mailbox auditing; glance drops to Improvement' {
        $raw = [pscustomobject]@{ status = 'Ok'; error = $null; unifiedAuditEnabled = $true; orgStatus = 'Ok'; mailboxAuditingDisabled = $true }
        $sec = Invoke-PpaAuditAnalyzer -Raw $raw -LicenseMap $script:Map
        $f = FindingOf $sec 'AUD-04'
        $f.status | Should -Be 'Improvement'
        $f.table.rows[0].cells[1] | Should -Be 'Disabled (AuditDisabled = true)'
        $f.table.rows[1].cells[0] | Should -Be 'Per-mailbox bypass'
        $sec.glance.status | Should -Be 'Improvement'
    }
    It 'AUD-04 Verify manually when the org read degrades - never a false Disabled; glance pill unaffected' {
        $raw = [pscustomobject]@{ status = 'Ok'; error = $null; unifiedAuditEnabled = $true; orgStatus = 'AccessDenied'; mailboxAuditingDisabled = $null }
        $sec = Invoke-PpaAuditAnalyzer -Raw $raw -LicenseMap $script:Map
        (FindingOf $sec 'AUD-04').status | Should -Be 'Verify manually'
        $sec.glance.status | Should -Be 'OK'
    }
}

Describe 'eDiscovery (evidence-only)' {
    It 'ED-01 inventories the cases; ED-02 is an Informational annotation' {
        (FindingOf $script:ED 'ED-01').title | Should -Be 'eDiscovery in use - 2 cases'
        @((FindingOf $script:ED 'ED-01').table.rows).Count | Should -Be 2
        $ed02 = FindingOf $script:ED 'ED-02'
        $ed02.status | Should -Be 'Informational'
        $ed02.table.rows[0].cells[1] | Should -Be 'Not assessed this session'
        $ed02.requires | Should -Match 'E5'
    }
}

Describe 'Insider Risk (assume E5, evidence verdicts)' {
    It 'enumeration unavailable -> Verify manually (unknown is not empty), never a claimed zero' {
        $f = FindingOf $script:IRM 'IRM-01'
        $f.status | Should -Be 'Verify manually'
        $f.table.rows[0].cells[1] | Should -Match 'Not readable'
        $f.requires | Should -Match 'E5'
    }
    It 'IRM-02 does not fire on an unknown inventory' {
        @($script:IRM.findings | Where-Object { $_.id -eq 'IRM-02' }).Count | Should -Be 0
    }
    It 'IRM-03 does not fire on an unknown inventory (absence never asserted from a failed read)' {
        @($script:IRM.findings | Where-Object { $_.id -eq 'IRM-03' }).Count | Should -Be 0
    }
    It 'genuinely empty -> a normal Improvement (like any empty workload) and IRM-02 fires' {
        $raw = [pscustomobject]@{ policies = [pscustomobject]@{ status = 'Ok'; error = $null; count = 0 } }
        $sec = Invoke-PpaInsiderRiskAnalyzer -Raw $raw -LicenseMap $script:Map
        $f = FindingOf $sec 'IRM-01'
        $f.status | Should -Be 'Improvement'
        $f.requires | Should -Match 'E5'
        $f2 = FindingOf $sec 'IRM-02'
        $f2.status | Should -Be 'Recommendation'
        $f2.table | Should -BeNullOrEmpty
    }
    It 'IRM-01 with real policy evidence is an inventory finding' {
        $raw = [pscustomobject]@{ policies = [pscustomobject]@{ status = 'Ok'; error = $null; count = 3 } }
        $sec = Invoke-PpaInsiderRiskAnalyzer -Raw $raw -LicenseMap $script:Map
        (FindingOf $sec 'IRM-01').title | Should -Be 'IRM in use - 3 policies'
        @($sec.findings | Where-Object { $_.id -eq 'IRM-02' }).Count | Should -Be 0
    }
    It 'IRM-01 renders per-policy rows when the collector projected items' {
        $raw = [pscustomobject]@{ policies = [pscustomobject]@{ status = 'Ok'; error = $null; count = 1; items = @(
            [pscustomobject]@{ name = 'Data leaks'; scenario = 'DataLeak'; workloads = 'Exchange, SharePoint'; created = '2026-01-15' }
        ) } }
        $sec = Invoke-PpaInsiderRiskAnalyzer -Raw $raw -LicenseMap $script:Map
        $f = FindingOf $sec 'IRM-01'
        $f.table.columns[1] | Should -Be 'Scenario'
        $f.table.rows[0].cells[0] | Should -Be 'Data leaks'
        $f.table.rows[0].cells[1] | Should -Be 'DataLeak'
    }
}

Describe 'Insider Risk - IRM-03 risky-AI template (spec F5)' {
    It 'no AI-scenario policy -> Recommendation with the not-being-scored whyline' {
        $raw = [pscustomobject]@{ policies = [pscustomobject]@{ status = 'Ok'; error = $null; count = 0; items = @() } }
        $sec = Invoke-PpaInsiderRiskAnalyzer -Raw $raw -LicenseMap $script:Map
        $f = FindingOf $sec 'IRM-03'
        $f.status | Should -Be 'Recommendation'
        $f.whyline | Should -Match 'prompt-injection'
        $f.requires | Should -Match 'E5'
    }
    It 'non-AI policies alone still leave IRM-03 as Recommendation' {
        $raw = [pscustomobject]@{ policies = [pscustomobject]@{ status = 'Ok'; error = $null; count = 1; items = @(
            [pscustomobject]@{ name = 'Departing employees'; scenario = 'DataTheft'; workloads = 'Exchange'; created = '' }
        ) } }
        (FindingOf (Invoke-PpaInsiderRiskAnalyzer -Raw $raw -LicenseMap $script:Map) 'IRM-03').status | Should -Be 'Recommendation'
    }
    It 'AI-scenario policy -> OK with name, scenario, workloads and created in the drill-down' {
        $raw = [pscustomobject]@{ policies = [pscustomobject]@{ status = 'Ok'; error = $null; count = 2; items = @(
            [pscustomobject]@{ name = 'Departing employees'; scenario = 'DataTheft'; workloads = 'Exchange'; created = '' }
            [pscustomobject]@{ name = 'Risky AI usage'; scenario = 'RiskyAIUsage'; workloads = 'Copilot'; created = '2026-06-30' }
        ) } }
        $f = FindingOf (Invoke-PpaInsiderRiskAnalyzer -Raw $raw -LicenseMap $script:Map) 'IRM-03'
        $f.status | Should -Be 'OK'
        @($f.table.rows).Count | Should -Be 1
        $f.table.rows[0].cells[0] | Should -Be 'Risky AI usage'
        $f.table.rows[0].cells[1] | Should -Be 'RiskyAIUsage'
        $f.table.rows[0].cells[3] | Should -Be '2026-06-30'
        $f.table.rows[0].remark | Should -Match 'corroborates'
    }
    It 'scenario matching has word-boundary care (CamelCase AI matches; incidental ai does not)' {
        Test-PpaIrmAiScenario 'RiskyAIUsage' | Should -BeTrue
        Test-PpaIrmAiScenario 'AI usage' | Should -BeTrue
        Test-PpaIrmAiScenario 'risky_ai' | Should -BeTrue
        Test-PpaIrmAiScenario 'DataLeak' | Should -BeFalse
        Test-PpaIrmAiScenario 'Maintenance' | Should -BeFalse
        Test-PpaIrmAiScenario '' | Should -BeFalse
    }
}

Describe 'Insider Risk collector - TenantSetting pseudo-policy exclusion (spec F5, VERIFIED)' {
    It 'excludes InsiderRiskScenario=TenantSetting from count and items' {
        Mock Invoke-PpaReadCmdlet {
            [pscustomobject]@{ Name = 'Get-InsiderRiskPolicy'; Status = 'Ok'; Error = $null; Data = @(
                [pscustomobject]@{ Name = 'IRM_Tenant_Setting_00000000-0000-0000-0000-000000000000'; InsiderRiskScenario = 'TenantSetting' }
                [pscustomobject]@{ Name = 'Data leaks'; InsiderRiskScenario = 'DataLeak'; Workload = @('Exchange', 'SharePoint'); WhenCreated = '2026-01-15T09:00:00Z' }
            ) }
        }
        $raw = Get-PpaInsiderRisk
        $raw.policies.count | Should -Be 1
        @($raw.policies.items).Count | Should -Be 1
        $raw.policies.items[0].name | Should -Be 'Data leaks'
        $raw.policies.items[0].scenario | Should -Be 'DataLeak'
        $raw.policies.items[0].workloads | Should -Be 'Exchange, SharePoint'
        $raw.policies.items[0].created | Should -Be '2026-01-15'
    }
    It 'a tenant with ONLY the pseudo-policy reports zero policies (the bug this fixes)' {
        Mock Invoke-PpaReadCmdlet {
            [pscustomobject]@{ Name = 'Get-InsiderRiskPolicy'; Status = 'Ok'; Error = $null; Data = @(
                [pscustomobject]@{ Name = 'IRM_Tenant_Setting_00000000-0000-0000-0000-000000000000'; InsiderRiskScenario = 'TenantSetting' }
            ) }
        }
        $raw = Get-PpaInsiderRisk
        $raw.policies.count | Should -Be 0
        @($raw.policies.items).Count | Should -Be 0
    }
    It 'a failed read still yields a null count (unknown is not zero)' {
        Mock Invoke-PpaReadCmdlet {
            [pscustomobject]@{ Name = 'Get-InsiderRiskPolicy'; Status = 'AccessDenied'; Error = 'Access is denied.'; Data = @() }
        }
        (Get-PpaInsiderRisk).policies.count | Should -BeNullOrEmpty
    }
}

Describe 'Communication Compliance (assume E5, evidence verdicts)' {
    It 'zero policies -> a normal Improvement with the Requires annotation riding along' {
        $f = FindingOf $script:CC 'CC-01'
        $f.status | Should -Be 'Improvement'
        $f.requires | Should -Match 'E5'
    }
}

Describe 'DSPM for AI (evidence from S&C artifacts)' {
    It 'artifacts present -> AI-01 in scope, AI-02 audit-only Improvement, AI-03 Recommendation' {
        $s = Statuses $script:DSPM
        $s['AI-01'] | Should -Be 'Informational'
        $s['AI-02'] | Should -Be 'Improvement'
        $s['AI-03'] | Should -Be 'Recommendation'
        (FindingOf $script:DSPM 'AI-01').title | Should -Match 'AI surface in scope'
    }
    It 'AI-03 tests the label-based exclusion control with no placeholder rows' {
        $f = FindingOf $script:DSPM 'AI-03'
        $f.title | Should -Be 'No label-based Copilot content exclusion'
        ($f.table.rows | Where-Object { $_.cells[0] -like 'Copilot-location rules*' }).cells[1] | Should -Be 'None detected'
        @($f.table.rows | Where-Object { $_.cells[1] -match 'Inventory not collected' }).Count | Should -Be 0
    }
    It 'AI-03 is OK when a Copilot-location rule references sensitivity labels' {
        $raw = [pscustomobject]@{ copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(
            [pscustomobject]@{ name = 'DSPM for AI - Protect labeled content'; mode = 'Enable'; sits = @(); hasLabelCondition = $true; labelRefs = @('Highly Confidential') }
        ) } }
        $sec = Invoke-PpaDspmAiAnalyzer -Raw $raw -LicenseMap $script:Map -HasSiteLabels:$true
        $f = $sec.findings | Where-Object { $_.id -eq 'AI-03' }
        $f.status | Should -Be 'OK'
        $f.title | Should -Be 'Label-based Copilot content exclusion configured'
        ($f.table.rows | Where-Object { $_.cells[0] -like 'Copilot-location rules*' }).cells[1] | Should -Match 'Highly Confidential'
    }
    It 'AI-02 carries the prompt-vs-labeled-content licensing split annotation' {
        (FindingOf $script:DSPM 'AI-02').requires | Should -Match 'Prompt DLP'
    }
    It 'zero artifacts -> AI-01 not-detectable plus AI-02 Recommendation (E5-included absence is a gap)' {
        $raw = [pscustomobject]@{ copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(); thirdPartyAiDlpPolicies = @() } }
        $sec = Invoke-PpaDspmAiAnalyzer -Raw $raw -LicenseMap $script:Map -HasSiteLabels:$false
        $f1 = $sec.findings | Where-Object { $_.id -eq 'AI-01' }
        $f1.title | Should -Match 'not detectable'
        @($f1.table.rows | Where-Object { $_.status -eq 'Verify manually' }).Count | Should -Be 1
        $f2 = $sec.findings | Where-Object { $_.id -eq 'AI-02' }
        $f2.status | Should -Be 'Recommendation'
        $f2.whyline | Should -Match 'not governed by any DLP policy'
        @($sec.findings | Where-Object { $_.id -eq 'AI-03' }).Count | Should -Be 0
    }
    It 'carries the NEW group tag' {
        $script:DSPM.groupTag | Should -Be 'NEW'
    }
}

Describe 'DSPM for AI - Copilot DLP posture upgrade (spec F2)' {
    It 'all policies in Enable mode -> AI-02 OK' {
        $raw = [pscustomobject]@{ copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(
            [pscustomobject]@{ name = 'Copilot DLP'; mode = 'Enable'; sits = @('U.S. SSN'); hasLabelCondition = $false; labelRefs = @(); copilotLocations = @('Copilot.M365'); oneClick = $false; parseFallback = $false; created = '2026-06-01' }
        ); thirdPartyAiDlpPolicies = @() } }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw $raw -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-02' }
        $f.status | Should -Be 'OK'
        $f.table.rows[0].cells[2] | Should -Be 'Enable'
        $f.table.rows[0].cells[3] | Should -Be '2026-06-01'
    }
    It 'one-click default in TestWithoutNotifications -> Improvement naming the mode, one-click tag in remark' {
        $raw = [pscustomobject]@{ copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(
            [pscustomobject]@{ name = 'Default DLP policy - Protect sensitive M365 Copilot interactions'; mode = 'TestWithoutNotifications'; sits = @(); hasLabelCondition = $false; labelRefs = @(); copilotLocations = @('Copilot.M365'); oneClick = $true; parseFallback = $false; created = '' }
        ); thirdPartyAiDlpPolicies = @() } }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw $raw -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-02' }
        $f.status | Should -Be 'Improvement'
        $f.whyline | Should -Match 'TestWithoutNotifications'
        $f.whyline | Should -Match 'simulation'
        $f.table.rows[0].remark | Should -Match 'one-click default'
    }
    It 'JSON parse fallback surfaces a reduced-confidence remark' {
        $raw = [pscustomobject]@{ copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(
            [pscustomobject]@{ name = 'Copilot DLP'; mode = 'Enable'; sits = @(); hasLabelCondition = $false; labelRefs = @(); copilotLocations = @('Copilot.M365'); oneClick = $false; parseFallback = $true; created = '' }
        ); thirdPartyAiDlpPolicies = @() } }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw $raw -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-02' }
        $f.table.rows[0].remark | Should -Match 'reduced confidence'
    }
    It 'third-party AI app DLP locations render an Informational row when populated, silent when empty' {
        $rawTp = [pscustomobject]@{ copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(); thirdPartyAiDlpPolicies = @('Contoso third-party AI') } }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw $rawTp -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-02' }
        $tpRows = @($f.table.rows | Where-Object { $_.cells[0] -match 'Third-party' })
        $tpRows.Count | Should -Be 1
        $tpRows[0].status | Should -Be 'Informational'
        $rawNone = [pscustomobject]@{ copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(); thirdPartyAiDlpPolicies = @() } }
        $fNone = (Invoke-PpaDspmAiAnalyzer -Raw $rawNone -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-02' }
        @($fNone.table.rows | Where-Object { $_.cells[0] -match 'Third-party' }).Count | Should -Be 0
    }
    It 'DLP read did not complete -> Verify manually, no absence verdict' {
        $raw = [pscustomobject]@{ copilotPolicies = [pscustomobject]@{ status = 'AccessDenied'; error = 'Access is denied.'; items = @(); thirdPartyAiDlpPolicies = @() } }
        $sec = Invoke-PpaDspmAiAnalyzer -Raw $raw -LicenseMap $script:Map
        ($sec.findings | Where-Object { $_.id -eq 'AI-01' }).status | Should -Be 'Verify manually'
        @($sec.findings | Where-Object { $_.id -eq 'AI-02' }).Count | Should -Be 0
        $sec.glance.metric | Should -Be 'not readable'
    }
}

Describe 'DSPM for AI - collection policies AI-04 (spec F1, above-E5 rule)' {
    It 'sandbox shape (readable, zero objects) -> Informational with the PAYG/Agent 365 licensing line, never a gap' {
        $f = FindingOf $script:DSPM 'AI-04'
        $f.status | Should -Be 'Informational'
        $f.title | Should -Match 'No DSPM collection policies'
        $f.whyline | Should -Match 'pay-as-you-go'
        $f.whyline | Should -Match 'Agent 365'
    }
    It 'renders unknown-schema objects dynamically (property/value rows)' {
        $raw = [pscustomobject]@{
            copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(); thirdPartyAiDlpPolicies = @() }
            dspmPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(
                [pscustomobject]@{ name = 'Capture policy A'; props = @(
                    [pscustomobject]@{ n = 'Name'; v = 'Capture policy A' }
                    [pscustomobject]@{ n = 'SomeFutureProperty'; v = 'SomeValue' }
                ) }
            ) }
        }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw $raw -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-04' }
        $f.status | Should -Be 'Informational'
        $f.title | Should -Match 'configured: 1'
        $f.table.rows[0].cells[0] | Should -Be 'Capture policy A'
        $f.table.rows[1].cells[1] | Should -Be 'SomeFutureProperty'
        $f.table.rows[1].cells[2] | Should -Be 'SomeValue'
    }
    It 'CommandNotFound -> Informational transparency note (surface not exposed, no severity)' {
        $raw = [pscustomobject]@{
            copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(); thirdPartyAiDlpPolicies = @() }
            dspmPolicies = [pscustomobject]@{ status = 'CommandNotFound'; error = 'Cmdlet not available.'; items = @() }
        }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw $raw -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-04' }
        $f.status | Should -Be 'Informational'
        $f.title | Should -Match 'not exposed'
    }
    It 'AccessDenied -> Verify manually' {
        $raw = [pscustomobject]@{
            copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(); thirdPartyAiDlpPolicies = @() }
            dspmPolicies = [pscustomobject]@{ status = 'AccessDenied'; error = 'Access is denied.'; items = @() }
        }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw $raw -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-04' }
        $f.status | Should -Be 'Verify manually'
    }
    It 'raw shapes that predate the sub-read do not sprout an AI-04' {
        $raw = [pscustomobject]@{ copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(); thirdPartyAiDlpPolicies = @() } }
        @((Invoke-PpaDspmAiAnalyzer -Raw $raw -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-04' }).Count | Should -Be 0
    }
}

Describe 'DSPM for AI - Copilot retention coverage AI-05 (spec F3)' {
    BeforeAll {
        function ArRaw($appRet, $legacy) {
            [pscustomobject]@{
                copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(); thirdPartyAiDlpPolicies = @() }
                appRetention = $appRet
                retentionLegacy = $legacy
            }
        }
        $script:LegacyEmpty = [pscustomobject]@{ status = 'Ok'; error = $null; totalCount = 0; teamsChatPolicies = @() }
    }
    It 'sandbox shape (zero retention of any kind) -> a clean Recommendation, never a crash or blank' {
        $f = FindingOf $script:DSPM 'AI-05'
        $f.status | Should -Be 'Recommendation'
        $f.title | Should -Match 'No retention lifecycle for Copilot'
        Test-PpaStatus $f.status | Should -BeTrue
    }
    It 'retention exists elsewhere but no Copilot coverage -> Improvement' {
        $appRet = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() }
        $legacy = [pscustomobject]@{ status = 'Ok'; error = $null; totalCount = 3; teamsChatPolicies = @() }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw (ArRaw $appRet $legacy) -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-05' }
        $f.status | Should -Be 'Improvement'
        $f.whyline | Should -Match 'no retention/deletion lifecycle'
    }
    It 'App policy with Applications matching M365Copilot -> OK with policy name and Enabled state' {
        $appRet = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(
            [pscustomobject]@{ name = 'Copilot interactions - 1yr'; enabled = 'True'; hasApplications = $true; applications = @('User:M365Copilot'); copilotCovered = $true }
        ) }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw (ArRaw $appRet $script:LegacyEmpty) -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-05' }
        $f.status | Should -Be 'OK'
        $f.table.rows[0].cells[0] | Should -Be 'Copilot interactions - 1yr'
        $f.table.rows[0].cells[1] | Should -Match 'User:M365Copilot'
        $f.table.rows[0].cells[1] | Should -Match 'Enabled: True'
    }
    It 'Applications property absent (schema drift) -> Verify manually with the not-assertable line, inventory rendered' {
        $appRet = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(
            [pscustomobject]@{ name = 'App policy X'; enabled = 'True'; hasApplications = $false; applications = @(); copilotCovered = $false }
        ) }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw (ArRaw $appRet $script:LegacyEmpty) -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-05' }
        $f.status | Should -Be 'Verify manually'
        $f.whyline | Should -Match 'not assertable from cmdlet output'
        $f.table.rows[0].cells[0] | Should -Be 'App policy X'
    }
    It 'legacy TeamsChatLocation policies render a transparency row without asserting coverage' {
        $appRet = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() }
        $legacy = [pscustomobject]@{ status = 'Ok'; error = $null; totalCount = 1; teamsChatPolicies = @('Teams chats retention') }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw (ArRaw $appRet $legacy) -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-05' }
        $f.status | Should -Be 'Improvement'
        $legRow = @($f.table.rows | Where-Object { $_.cells[0] -match 'Legacy combined' })
        $legRow.Count | Should -Be 1
        $legRow[0].status | Should -Be 'Informational'
        $legRow[0].remark | Should -Match 'not asserted'
    }
    It 'unknown AI-app tokens are reported verbatim as Informational; none -> the PAYG licensing row' {
        $appRet = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(
            [pscustomobject]@{ name = 'AI apps policy'; enabled = 'True'; hasApplications = $true; applications = @('User:M365Copilot', 'User:EnterpriseAIApps'); copilotCovered = $true }
        ) }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw (ArRaw $appRet $script:LegacyEmpty) -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-05' }
        $tok = @($f.table.rows | Where-Object { $_.cells[0] -match 'verbatim' })
        $tok.Count | Should -Be 1
        $tok[0].cells[1] | Should -Match 'EnterpriseAIApps'
        $fNone = FindingOf $script:DSPM 'AI-05'
        @($fNone.table.rows | Where-Object { $_.cells[1] -eq 'None detected' -and $_.remark -match 'pay-as-you-go' }).Count | Should -Be 1
    }
    It 'app retention read failed -> Verify manually via the degradation helper, no absence verdict' {
        $appRet = [pscustomobject]@{ status = 'AccessDenied'; error = 'Access is denied.'; items = @() }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw (ArRaw $appRet $script:LegacyEmpty) -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-05' }
        $f.status | Should -Be 'Verify manually'
        $f.title | Should -Match 'not readable'
    }
}

Describe 'DSPM for AI - CC Copilot monitoring AI-06 (spec F4, VERIFIED)' {
    BeforeAll {
        function CcRaw($cc) {
            [pscustomobject]@{
                copilotPolicies = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(); thirdPartyAiDlpPolicies = @() }
                ccCopilot = $cc
            }
        }
    }
    It 'no Copilot-scoped CC policy -> Recommendation naming the one-step template' {
        $f = FindingOf $script:DSPM 'AI-06'
        $f.status | Should -Be 'Recommendation'
        $f.whyline | Should -Match 'Detect Microsoft 365 Copilot interactions'
        $f.requires | Should -Match 'E5'
    }
    It 'Copilot-scoped and enabled -> OK with workloads from the rule in the drill-down' {
        $cc = [pscustomobject]@{ policiesStatus = 'Ok'; policiesError = $null; rulesStatus = 'Ok'; rulesError = $null; items = @(
            [pscustomobject]@{ name = 'Microsoft 365 Copilot interactions'; enabled = 'True'; workloads = @('Copilot'); unifiedGenAI = $null; thirdParty = $null; parseFallback = $false; hasRule = $true }
        ) }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw (CcRaw $cc) -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-06' }
        $f.status | Should -Be 'OK'
        $f.table.rows[0].cells[0] | Should -Be 'Microsoft 365 Copilot interactions'
        $f.table.rows[0].cells[2] | Should -Be 'Copilot'
    }
    It 'Copilot-scoped but disabled -> Improvement' {
        $cc = [pscustomobject]@{ policiesStatus = 'Ok'; policiesError = $null; rulesStatus = 'Ok'; rulesError = $null; items = @(
            [pscustomobject]@{ name = 'Microsoft 365 Copilot interactions'; enabled = 'False'; workloads = @('Copilot'); unifiedGenAI = $null; thirdParty = $null; parseFallback = $false; hasRule = $true }
        ) }
        ((Invoke-PpaDspmAiAnalyzer -Raw (CcRaw $cc) -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-06' }).status | Should -Be 'Improvement'
    }
    It 'a CC policy scoping other workloads only is not Copilot coverage' {
        $cc = [pscustomobject]@{ policiesStatus = 'Ok'; policiesError = $null; rulesStatus = 'Ok'; rulesError = $null; items = @(
            [pscustomobject]@{ name = 'Teams monitoring'; enabled = 'True'; workloads = @('Teams', 'Exchange'); unifiedGenAI = $null; thirdParty = $null; parseFallback = $false; hasRule = $true }
        ) }
        ((Invoke-PpaDspmAiAnalyzer -Raw (CcRaw $cc) -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-06' }).status | Should -Be 'Recommendation'
    }
    It 'PAYG-gated GenAI / third-party channels render only when non-null' {
        $cc = [pscustomobject]@{ policiesStatus = 'Ok'; policiesError = $null; rulesStatus = 'Ok'; rulesError = $null; items = @(
            [pscustomobject]@{ name = 'Copilot CC'; enabled = 'True'; workloads = @('Copilot'); unifiedGenAI = 'ChatGPT Enterprise'; thirdParty = $null; parseFallback = $false; hasRule = $true }
        ) }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw (CcRaw $cc) -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-06' }
        @($f.table.rows | Where-Object { $_.cells[0] -match 'Unified GenAI' }).Count | Should -Be 1
        @($f.table.rows | Where-Object { $_.cells[0] -match 'Third-party workloads' }).Count | Should -Be 0
        $fNone = FindingOf $script:DSPM 'AI-06'
        @($fNone.table.rows | Where-Object { $_.cells[0] -match 'Unified GenAI|Third-party workloads' }).Count | Should -Be 0
    }
    It 'carries the one-line IRM cross-reference (spec rule 7)' {
        $f = FindingOf $script:DSPM 'AI-06'
        @($f.table.rows | Where-Object { $_.cells[1] -match 'Insider Risk Management section' }).Count | Should -Be 1
    }
    It 'AccessDenied on either cmdlet -> Verify manually naming the CC role group' {
        $cc = [pscustomobject]@{ policiesStatus = 'Ok'; policiesError = $null; rulesStatus = 'AccessDenied'; rulesError = 'Access is denied.'; items = @() }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw (CcRaw $cc) -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-06' }
        $f.status | Should -Be 'Verify manually'
        $f.table.rows[0].remark | Should -Match 'Communication Compliance role group'
    }
    It 'CommandNotFound -> Informational transparency note' {
        $cc = [pscustomobject]@{ policiesStatus = 'CommandNotFound'; policiesError = 'Cmdlet not available.'; rulesStatus = 'CommandNotFound'; rulesError = 'Cmdlet not available.'; items = @() }
        $f = (Invoke-PpaDspmAiAnalyzer -Raw (CcRaw $cc) -LicenseMap $script:Map).findings | Where-Object { $_.id -eq 'AI-06' }
        $f.status | Should -Be 'Informational'
        $f.title | Should -Match 'not exposed'
    }
}

Describe 'DSPM collector - CC Copilot scoping (spec F4, VERIFIED ContentSources shape)' {
    It 'parses the verified ContentSources JSON: Workloads=[Copilot], null GenAI/third-party channels' {
        $pols = @([pscustomobject]@{ Name = 'Microsoft 365 Copilot interactions'; Enabled = $true })
        $rules = @([pscustomobject]@{ Name = 'Microsoft 365 Copilot interactions'
            ContentSources = '{"RevieweeName":"AllUsersGroupsOfTenant","Workloads":["Copilot"],"ThirdPartyWorkloads":null,"UnifiedGenAIWorkloads":null}' })
        $items = @(Get-PpaCcCopilotItems $pols $rules)
        $items.Count | Should -Be 1
        @($items[0].workloads) | Should -Contain 'Copilot'
        $items[0].unifiedGenAI | Should -BeNullOrEmpty
        $items[0].thirdParty | Should -BeNullOrEmpty
        $items[0].parseFallback | Should -BeFalse
        $items[0].hasRule | Should -BeTrue
    }
    It 'associates rule to policy by the policy reference property when names differ' {
        $pols = @([pscustomobject]@{ Name = 'CC policy A'; Guid = '11111111-1111-1111-1111-111111111111'; Enabled = $true })
        $rules = @([pscustomobject]@{ Name = 'rule-x'; Policy = '11111111-1111-1111-1111-111111111111'
            ContentSources = '{"Workloads":["Copilot"],"ThirdPartyWorkloads":null,"UnifiedGenAIWorkloads":null}' })
        $items = @(Get-PpaCcCopilotItems $pols $rules)
        @($items[0].workloads) | Should -Contain 'Copilot'
    }
    It 'captures non-null UnifiedGenAI / ThirdParty channel values' {
        $pols = @([pscustomobject]@{ Name = 'CC AI'; Enabled = $true })
        $rules = @([pscustomobject]@{ Name = 'CC AI'
            ContentSources = '{"Workloads":["Copilot"],"ThirdPartyWorkloads":["SomeApp"],"UnifiedGenAIWorkloads":["ChatGPT Enterprise"]}' })
        $items = @(Get-PpaCcCopilotItems $pols $rules)
        $items[0].unifiedGenAI | Should -Be 'ChatGPT Enterprise'
        $items[0].thirdParty | Should -Be 'SomeApp'
    }
    It 'falls back to regex containment on malformed ContentSources and flags reduced confidence' {
        $pols = @([pscustomobject]@{ Name = 'CC broken'; Enabled = $true })
        $rules = @([pscustomobject]@{ Name = 'CC broken'; ContentSources = '{"Workloads":["Copilot"], TRUNCATED' })
        $items = @(Get-PpaCcCopilotItems $pols $rules)
        @($items[0].workloads) | Should -Contain 'Copilot'
        $items[0].parseFallback | Should -BeTrue
    }
    It 'a policy with no matching rule yields empty workloads (never a false Copilot claim)' {
        $pols = @([pscustomobject]@{ Name = 'Orphan policy'; Enabled = $true })
        $items = @(Get-PpaCcCopilotItems $pols @())
        @($items[0].workloads).Count | Should -Be 0
        $items[0].hasRule | Should -BeFalse
    }
}

Describe 'DSPM collector - Copilot DLP detection signals (spec F2, VERIFIED keys)' {
    It 'detects via EnforcementPlanes containing CopilotExperiences' {
        $p = [pscustomobject]@{ Name = 'Anything'; EnforcementPlanes = @('CopilotExperiences') }
        (Get-PpaCopilotDlpSignals $p).isCopilot | Should -BeTrue
    }
    It 'detects via Locations JSON (Workload=Applications, Location=Copilot.M365) and reports the location' {
        $p = [pscustomobject]@{ Name = 'Anything'; Locations = '[{"Workload":"Applications","Location":"Copilot.M365","LocationSource":"PurviewConfig"}]' }
        $s = Get-PpaCopilotDlpSignals $p
        $s.isCopilot | Should -BeTrue
        @($s.copilotLocations) | Should -Contain 'Copilot.M365'
        $s.parseFallback | Should -BeFalse
    }
    It 'falls back to regex containment on malformed Locations JSON and flags reduced confidence' {
        $p = [pscustomobject]@{ Name = 'Anything'; Locations = '[{"Workload":"Applications","Location":"Copilot.M365", TRUNCATED' }
        $s = Get-PpaCopilotDlpSignals $p
        $s.isCopilot | Should -BeTrue
        @($s.copilotLocations) | Should -Contain 'Copilot.M365'
        $s.parseFallback | Should -BeTrue
    }
    It 'never flags on name alone (names are admin-editable)' {
        $p = [pscustomobject]@{ Name = 'DSPM for AI - Copilot policy'; Locations = '[{"Workload":"Exchange","Location":"All"}]' }
        (Get-PpaCopilotDlpSignals $p).isCopilot | Should -BeFalse
    }
    It 'fingerprints the Microsoft one-click default (name prefix + comment + PurviewConfig)' {
        $p = [pscustomobject]@{
            Name = 'Default DLP policy - Protect sensitive M365 Copilot interactions'
            Comment = 'Prevent data leakage and oversharing by restricting Microsoft 365 Copilot from processing sensitive content.'
            Locations = '[{"Workload":"Applications","Location":"Copilot.M365","LocationSource":"PurviewConfig"}]'
        }
        (Get-PpaCopilotDlpSignals $p).oneClick | Should -BeTrue
    }
    It 'does not fingerprint an admin-authored Copilot policy' {
        $p = [pscustomobject]@{ Name = 'Contoso Copilot DLP'; Comment = 'Our own policy.'; Locations = '[{"Workload":"Applications","Location":"Copilot.M365"}]' }
        (Get-PpaCopilotDlpSignals $p).oneClick | Should -BeFalse
    }
    It 'end to end: collector projects locations, one-click tag and third-party carrier names' {
        Mock Invoke-PpaReadCmdlet {
            if ($Name -eq 'Get-DlpCompliancePolicy') {
                [pscustomobject]@{ Name = $Name; Status = 'Ok'; Error = $null; Data = @(
                    [pscustomobject]@{
                        Name = 'Default DLP policy - Protect sensitive M365 Copilot interactions'
                        Mode = 'TestWithoutNotifications'
                        Comment = 'Prevent data leakage and oversharing by restricting Microsoft 365 Copilot from processing content.'
                        Locations = '[{"Workload":"Applications","Location":"Copilot.M365","LocationSource":"PurviewConfig"}]'
                        WhenCreated = '2026-06-30T08:00:00Z'
                    }
                    [pscustomobject]@{ Name = 'EXO only'; Mode = 'Enable'; Locations = '[{"Workload":"Exchange","Location":"All"}]'; ThirdPartyAppDlpLocation = @('SomeAiApp') }
                ) }
            }
            else {
                [pscustomobject]@{ Name = $Name; Status = 'Ok'; Error = $null; Data = @() }
            }
        }
        $raw = Get-PpaDspmAi
        @($raw.copilotPolicies.items).Count | Should -Be 1
        $raw.copilotPolicies.items[0].mode | Should -Be 'TestWithoutNotifications'
        $raw.copilotPolicies.items[0].oneClick | Should -BeTrue
        $raw.copilotPolicies.items[0].created | Should -Be '2026-06-30'
        @($raw.copilotPolicies.items[0].copilotLocations) | Should -Contain 'Copilot.M365'
        @($raw.copilotPolicies.thirdPartyAiDlpPolicies) | Should -Contain 'EXO only'
    }
}
