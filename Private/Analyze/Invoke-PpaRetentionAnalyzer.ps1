# Invoke-PpaRetentionAnalyzer.ps1 - analyzer for section 03 (Retention & Records).
# Produces RET-01..03 per CHECK_CATALOG.md. Pure function of its input.
# ASCII-only source (Windows PowerShell 5.1). Depends on New-PpaFinding/New-PpaSection.

Set-StrictMode -Off

function Invoke-PpaRetentionAnalyzer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Raw,
        # Parsed Data/license-requirements.json (static annotation map, not detection).
        $LicenseMap
    )

    $mid    = Get-PpaMidDot
    $pols   = @($Raw.policies.items)
    $labels = @($Raw.labels.items)
    $adaptiveScopeCount = [int]$Raw.adaptiveScopes.count
    $findings = New-Object System.Collections.Generic.List[object]

    # --- RET-01: inventory of policies & labels ---
    # F-001: a failed policy read must not report "0 policies" as fact (unknown != empty).
    $lm01 = @(@{ label = 'Learn about retention policies & labels'; url = 'https://learn.microsoft.com/en-us/purview/retention'; tag = 'docs' })
    if ([string]$Raw.policies.status -ne 'Ok') {
        $findings.Add((New-PpaFinding -Id 'RET-01' -DomId 'f-ret-1' -Title 'Retention policies not readable this session' -Status 'Verify manually' `
            -Whyline 'Retention policies could not be enumerated this session, so retention posture was not evaluated - confirm in the Purview portal.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @((New-PpaRow -Cells @('Retention policies', 'Not readable this session') -Status 'Verify manually' -Remark ([string]$Raw.policies.error)))) -LearnMore $lm01))
    }
    elseif ($pols.Count -eq 0) {
        $findings.Add((New-PpaFinding -Id 'RET-01' -DomId 'f-ret-1' -Title 'No retention policies configured' -Status 'Improvement' `
            -Whyline 'With no retention policies, data is neither retained for compliance nor disposed of on a schedule.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @((New-PpaRow -Cells @('Retention policies', '0') -Status 'Improvement'))) -LearnMore $lm01))
    }
    else {
        $rows01 = foreach ($p in $pols) {
            $scopeType = if ($p.adaptive) { 'Adaptive' } else { 'Static' }
            $remark = "$scopeType $mid " + (@($p.locations) -join ', ')
            New-PpaRow -Cells @($p.name, (@($p.labels) -join ', '), $remark) -Status 'Informational'
        }
        $findings.Add((New-PpaFinding -Id 'RET-01' -DomId 'f-ret-1' -Title "$($pols.Count) retention policies, $($labels.Count) retention labels" -Status 'Informational' `
            -Whyline "Baseline of what's being retained and where." `
            -Table (New-PpaTable -Columns @('Retention Policy', 'Labels', 'Remarks', 'Status') -Rows @($rows01)) -LearnMore $lm01))
    }

    # --- RET-02: adaptive scopes ---
    $lm02 = @(@{ label = 'Adaptive vs. static scopes'; url = 'https://learn.microsoft.com/en-us/purview/retention-policies-adaptive'; tag = 'docs' })
    if ([string]$Raw.adaptiveScopes.status -ne 'Ok') {
        # F-001: the adaptive-scope count is 0 only because the read did not complete.
        $findings.Add((New-PpaFinding -Id 'RET-02' -DomId 'f-ret-2' -Title 'Adaptive scopes not readable this session' -Status 'Verify manually' -Requires (Get-PpaRequirement $LicenseMap 'RET-02') `
            -Whyline 'Adaptive scopes could not be enumerated this session - confirm in the Purview portal.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @((New-PpaRow -Cells @('Adaptive scopes', 'Not readable this session') -Status 'Verify manually'))) -LearnMore $lm02))
    }
    else {
        $staticCount = @($pols | Where-Object { -not $_.adaptive }).Count
        $rows02 = @(
            New-PpaRow -Cells @('Static scopes', [string]$staticCount) -Status 'Informational'
            New-PpaRow -Cells @('Adaptive scopes', [string]$adaptiveScopeCount) -Status ($(if ($adaptiveScopeCount -gt 0) { 'OK' } else { 'Improvement' }))
        )
        $findings.Add((New-PpaFinding -Id 'RET-02' -DomId 'f-ret-2' -Title ($(if ($adaptiveScopeCount -gt 0) { 'Adaptive scopes in use' } else { 'No adaptive scopes' })) -Status ($(if ($adaptiveScopeCount -gt 0) { 'OK' } else { 'Improvement' })) -Requires (Get-PpaRequirement $LicenseMap 'RET-02') `
            -Whyline 'Static scopes drift as the org changes; adaptive scopes keep coverage current by attribute/query.' `
            -Table (New-PpaTable -Columns @('Scope type', 'Count', 'Status') -Rows $rows02) `
            -LearnMore $lm02))
    }

    # --- RET-03: manual-apply retention labels ---
    $manualNames = @($labels | Where-Object { -not $_.autoApply } | ForEach-Object { $_.name })
    $manualCount = $manualNames.Count
    $lm03 = @(@{ label = 'Auto-apply retention labels'; url = 'https://learn.microsoft.com/en-us/purview/apply-retention-labels-automatically'; tag = 'docs' })
    if ([string]$Raw.labels.status -ne 'Ok') {
        # F-001: a failed retention-rule read must not report "0 labels" as fact.
        $findings.Add((New-PpaFinding -Id 'RET-03' -DomId 'f-ret-3' -Title 'Retention labels not readable this session' -Status 'Verify manually' `
            -Whyline 'Retention labels could not be enumerated this session - confirm in the Purview portal.' `
            -Table (New-PpaTable -Columns @('Retention label', 'Auto-apply rule', 'Status') -Rows @((New-PpaRow -Cells @('Retention labels', 'Not readable this session') -Status 'Verify manually'))) -LearnMore $lm03))
    }
    elseif ($labels.Count -eq 0) {
        # Zero labels is NOT "all auto-apply" - there is simply nothing to judge here.
        $findings.Add((New-PpaFinding -Id 'RET-03' -DomId 'f-ret-3' -Title 'No retention labels defined' -Status 'Informational' `
            -Whyline 'There are no retention labels, so auto-apply does not come into play; retention relies on policies alone.' `
            -Table (New-PpaTable -Columns @('Retention label', 'Auto-apply rule', 'Status') -Rows @((New-PpaRow -Cells @('Retention labels', '0') -Status 'Informational'))) -LearnMore $lm03))
    }
    elseif ($manualCount -eq 0) {
        $findings.Add((New-PpaFinding -Id 'RET-03' -DomId 'f-ret-3' -Title 'Retention labels have auto-apply conditions' -Status 'OK' `
            -Whyline 'Auto-apply conditions remove reliance on users tagging content by hand.' `
            -Table (New-PpaTable -Columns @('Retention label', 'Auto-apply rule', 'Status') -Rows @((New-PpaRow -Cells @('Retention labels', 'All auto-apply') -Status 'OK'))) -LearnMore $lm03))
    }
    else {
        # Show the in-use (policy-attached) manual labels as rows; summarize the full total in a remark.
        $attached = @($pols | ForEach-Object { $_.labels } | Where-Object { $_ } | Select-Object -Unique)
        $displayNames = @($attached | Where-Object { $manualNames -contains $_ })
        if ($displayNames.Count -eq 0) { $displayNames = @($manualNames | Select-Object -First 5) }
        $rows03 = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $displayNames.Count; $i++) {
            $remark = $null
            if ($i -eq $displayNames.Count - 1) {
                $remark = "$manualCount of $($labels.Count) retention labels have no auto-apply (SIT / KQL / trainable) condition."
            }
            $rows03.Add((New-PpaRow -Cells @($displayNames[$i], 'None (manual)') -Status 'Improvement' -Remark $remark))
        }
        $findings.Add((New-PpaFinding -Id 'RET-03' -DomId 'f-ret-3' -Title 'Retention labels are manual-apply only' -Status 'Improvement' `
            -Whyline 'Retention outcomes depend on users tagging content, which is inconsistent at scale.' `
            -Table (New-PpaTable -Columns @('Retention label', 'Auto-apply rule', 'Status') -Rows $rows03.ToArray()) -LearnMore $lm03))
    }

    # --- glance ---
    if ([string]$Raw.policies.status -ne 'Ok') {
        $glance = New-PpaGlance -Name 'Retention & Records' -Metric 'not readable' -Sub 'confirm in portal'
    }
    else {
        $scopeState = if ($adaptiveScopeCount -gt 0) { 'adaptive + static' } else { 'static only' }
        $glance = New-PpaGlance -Name 'Retention & Records' -Metric "$($pols.Count) policies" -Sub "$($labels.Count) labels $mid $scopeState"
    }

    return New-PpaSection -Id 'Retention' -Title 'Retention & Records' -Group 'Data Lifecycle & Records' `
        -GroupIcon 'fas fa-archive' -Glance $glance -Findings $findings.ToArray()
}
