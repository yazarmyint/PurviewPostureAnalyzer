# Invoke-PpaInsiderRiskAnalyzer.ps1 - analyzer for section 04 (Insider Risk Management).
# Assume-E5 model (decision D9): verdicts come from evidence exactly like an E3 workload -
# policies returned -> inventory; genuinely empty -> a normal Improvement; unreadable ->
# Verify manually (unknown is never asserted as empty). The 'Requires' tier annotation
# rides alongside and never changes the verdict.
# Policy counts and inventories EXCLUDE the tenant-settings pseudo-policy
# (InsiderRiskScenario = TenantSetting) - the collector filters it (VERIFIED 2026-07-02).
# ASCII-only source. Depends on New-PpaFinding/New-PpaSection/Get-PpaRequirement.

Set-StrictMode -Off

function Test-PpaIrmAiScenario {
    # True when a policy's InsiderRiskScenario looks like the risky-AI-usage template.
    # The exact enum value is UNVERIFIED (no risky-AI policy existed in the 2026-07-02
    # sandbox) - when first observed on a populated tenant, record the exact
    # InsiderRiskScenario value here and tighten this to an -eq match.
    # Case-sensitive 'AI' catches CamelCase enums (e.g. RiskyAIUsage) without tripping on
    # unrelated lowercase substrings ('Maintenance'); the bounded case-insensitive
    # alternative catches spaced/underscored shapes ('AI usage', 'risky_ai').
    # Policy Name is corroboration only - never a detection signal on its own.
    param([string]$Scenario)
    if ([string]::IsNullOrEmpty($Scenario)) { return $false }
    return (($Scenario -cmatch 'AI') -or ($Scenario -match '(?i)(^|[^a-z0-9])ai([^a-z0-9]|$)'))
}

function Invoke-PpaInsiderRiskAnalyzer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Raw,
        $LicenseMap
    )

    $mid = Get-PpaMidDot
    $count = $Raw.policies.count          # $null when the read did not complete (D7)
    $items = @($Raw.policies.items | Where-Object { $null -ne $_ })   # absent on older raw shapes -> @()
    $req = Get-PpaRequirement $LicenseMap 'IRM-01'
    $findings = New-Object System.Collections.Generic.List[object]
    $lm01 = @(@{ label = 'Learn about Insider Risk Management'; url = 'https://learn.microsoft.com/en-us/purview/insider-risk-management'; tag = 'docs' })

    # --- IRM-01: evidence from Get-InsiderRiskPolicy ---
    if ($null -eq $count) {
        # Unreadable is not empty: never assert absence from a failed read.
        $findings.Add((New-PpaFinding -Id 'IRM-01' -DomId 'f-irm-1' -Title 'IRM policy inventory not readable this session' -Status 'Verify manually' -Requires $req `
            -Whyline 'IRM policies cannot be enumerated read-only from this session - confirm coverage in the Purview portal.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('IRM policies', 'Not readable read-only') -Status 'Verify manually'
            )) -LearnMore $lm01))
    }
    elseif ($count -eq 0) {
        # Empty workload -> a normal Improvement, same as any empty workload.
        $findings.Add((New-PpaFinding -Id 'IRM-01' -DomId 'f-irm-1' -Title 'No IRM policies configured' -Status 'Improvement' -Requires $req `
            -Whyline 'No insider-risk policy is scoring activity, so leaver data theft and risky-user signals go unwatched.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('IRM policies', '0') -Status 'Improvement'
            )) -LearnMore $lm01))
    }
    else {
        # Per-policy inventory when the collector projected items; count row otherwise.
        if ($items.Count -gt 0) {
            $rows01 = foreach ($p in $items) {
                New-PpaRow -Cells @([string]$p.name, [string]$p.scenario, [string]$p.workloads) -Status 'Informational'
            }
            $findings.Add((New-PpaFinding -Id 'IRM-01' -DomId 'f-irm-1' -Title "IRM in use - $count policies" -Status 'Informational' -Requires $req `
                -Whyline 'Insider-risk policies are scoring activity in the tenant.' `
                -Table (New-PpaTable -Columns @('IRM Policy', 'Scenario', 'Workloads', 'Status') -Rows @($rows01)) -LearnMore $lm01))
        }
        else {
            $findings.Add((New-PpaFinding -Id 'IRM-01' -DomId 'f-irm-1' -Title "IRM in use - $count policies" -Status 'Informational' -Requires $req `
                -Whyline 'Insider-risk policies are scoring activity in the tenant.' `
                -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                    New-PpaRow -Cells @('IRM policies', [string]$count) -Status 'Informational'
                )) -LearnMore $lm01))
        }
    }

    # --- IRM-02: advisory (fires on evidence of absence; unknown is not absent) ---
    if ($count -eq 0) {
        $findings.Add((New-PpaFinding -Id 'IRM-02' -DomId 'f-irm-2' -Title 'Consider IRM for departing-employee risk' -Status 'Recommendation' -Requires (Get-PpaRequirement $LicenseMap 'IRM-02') `
            -Whyline 'Data theft by leavers is a common uncovered scenario. Needs HR/Legal alignment before scoping - not a quick config win.' `
            -Table $null `
            -LearnMore @(@{ label = 'IRM policy templates'; url = 'https://learn.microsoft.com/en-us/purview/insider-risk-management-policies'; tag = 'docs' })))
    }

    # --- IRM-03: risky-AI-usage template coverage (spec F5) ---
    # Only assertable from a completed read; on a failed read the IRM-01 Verify-manually
    # degradation already covers the section (absence is never asserted from a failed read).
    if ($null -ne $count) {
        $lm03 = @(@{ label = 'IRM policy templates'; url = 'https://learn.microsoft.com/en-us/purview/insider-risk-management-policy-templates'; tag = 'docs' })
        $aiPolicies = @($items | Where-Object { Test-PpaIrmAiScenario ([string]$_.scenario) })
        if ($aiPolicies.Count -gt 0) {
            $rows03 = foreach ($p in $aiPolicies) {
                $remark = $null
                if ([string]$p.name -match '(?i)\bAI\b|copilot|risky') { $remark = 'Policy name corroborates the risky-AI template match.' }
                New-PpaRow -Cells @([string]$p.name, [string]$p.scenario, [string]$p.workloads, [string]$p.created) -Status 'OK' -Remark $remark
            }
            $findings.Add((New-PpaFinding -Id 'IRM-03' -DomId 'f-irm-3' -Title 'Risky AI usage policy in place' -Status 'OK' -Requires (Get-PpaRequirement $LicenseMap 'IRM-03') `
                -Whyline 'An Insider Risk policy with an AI scenario is scoring risky Copilot/AI usage signals such as prompt injection and protected-material access.' `
                -Table (New-PpaTable -Columns @('IRM Policy', 'Scenario', 'Workloads', 'Created', 'Status') -Rows @($rows03)) -LearnMore $lm03))
        }
        else {
            $findings.Add((New-PpaFinding -Id 'IRM-03' -DomId 'f-irm-3' -Title 'No Risky AI usage policy' -Status 'Recommendation' -Requires (Get-PpaRequirement $LicenseMap 'IRM-03') `
                -Whyline 'No Insider Risk policy based on the Risky AI usage template - prompt-injection and protected-material access signals from Copilot are not being scored.' `
                -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                    New-PpaRow -Cells @('IRM policies with an AI scenario', '0') -Status 'Recommendation'
                )) -LearnMore $lm03))
        }
    }

    # --- glance ---
    $metric = if ($null -eq $count) { 'not readable' } else { "$count policies" }
    $glance = New-PpaGlance -Name 'Insider Risk' -Metric $metric -Sub 'requires E5'

    return New-PpaSection -Id 'Insider_Risk' -Title 'Insider Risk Management' -Group 'Insider Risk' `
        -GroupIcon 'fas fa-user-secret' -Glance $glance -Findings $findings.ToArray()
}
