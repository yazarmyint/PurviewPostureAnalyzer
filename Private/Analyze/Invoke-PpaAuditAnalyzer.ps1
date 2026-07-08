# Invoke-PpaAuditAnalyzer.ps1 - analyzer for section 05 (Audit).
# Evidence-only: AUD-01 from Get-AdminAuditLogConfig; AUD-03 notes Premium retention is
# not readable this session; AUD-04 from Get-OrganizationConfig.AuditDisabled (the
# org-level mailbox auditing override - Wave 6 reincorporation Part 1). There is
# deliberately NO ingestion/latency finding in the report (client-facing polish):
# "enabled" vs "ingesting on time" is a real caveat, but it lives in LIMITATIONS.md /
# README, not as report clutter (AUD-02 stays reserved and un-emitted).
# ASCII-only source. Depends on New-PpaFinding/New-PpaSection/Get-PpaRequirement.

Set-StrictMode -Off

function Invoke-PpaAuditAnalyzer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Raw,
        $LicenseMap
    )

    $mid = Get-PpaMidDot
    # $null means "not read this session" (e.g. EXO not connected) - distinct from $false.
    $enabledKnown = ($null -ne $Raw.unifiedAuditEnabled)
    $enabled = $enabledKnown -and [bool]$Raw.unifiedAuditEnabled
    $findings = New-Object System.Collections.Generic.List[object]

    # --- AUD-01: unified audit logging (evidence) ---
    if (-not $enabledKnown) {
        $findings.Add((New-PpaFinding -Id 'AUD-01' -DomId 'f-aud-1' -Title 'Unified audit logging not readable this session' -Status 'Verify manually' `
            -Whyline 'Audit underpins investigations, eDiscovery, and IRM signals; the setting could not be read (Exchange Online session not established?).' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Unified audit logging', 'Not readable this session') -Status 'Verify manually'
            )) `
            -LearnMore @(@{ label = 'Learn about auditing solutions'; url = 'https://learn.microsoft.com/en-us/purview/audit-solutions-overview'; tag = 'docs' })))
    }
    else {
        $rows01 = @(
            New-PpaRow -Cells @('Unified audit logging', ($(if ($enabled) { 'Enabled' } else { 'Disabled' }))) -Status ($(if ($enabled) { 'OK' } else { 'Improvement' }))
            New-PpaRow -Cells @('Audit retention', 'Default (180 days) unless Audit (Premium) applies') -Status 'Informational'
        )
        $findings.Add((New-PpaFinding -Id 'AUD-01' -DomId 'f-aud-1' -Title ($(if ($enabled) { 'Unified audit logging is enabled' } else { 'Unified audit logging is disabled' })) -Status ($(if ($enabled) { 'OK' } else { 'Improvement' })) `
            -Whyline 'Audit underpins investigations, eDiscovery, and IRM signals.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows $rows01) `
            -LearnMore @(@{ label = 'Learn about auditing solutions'; url = 'https://learn.microsoft.com/en-us/purview/audit-solutions-overview'; tag = 'docs' })))
    }

    # --- AUD-03: Audit (Premium) retention - not readable this session; tier annotation rides along ---
    $findings.Add((New-PpaFinding -Id 'AUD-03' -DomId 'f-aud-3' -Title 'Audit (Premium) long-term retention not assessed' -Status 'Informational' -Requires (Get-PpaRequirement $LicenseMap 'AUD-03') `
        -Whyline 'Long-term audit retention bounds how far back an investigation can reach; premium retention configuration is not readable from this session.' `
        -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
            New-PpaRow -Cells @('Audit (Premium) long-term retention', 'Not assessed this session') -Status 'Informational'
        )) `
        -LearnMore @(@{ label = 'Audit (Premium)'; url = 'https://learn.microsoft.com/en-us/purview/audit-premium'; tag = 'docs' })))

    # --- AUD-04: mailbox auditing organization default (evidence) ---
    # $null means "not read this session" (org read failed or property absent) - the
    # absence of the read is never reported as Disabled.
    $mbxKnown    = ($null -ne $Raw.mailboxAuditingDisabled)
    $mbxDisabled = $mbxKnown -and [bool]$Raw.mailboxAuditingDisabled
    $whyMbx = 'Mailbox actions - delegate access, exports, deletions - are core investigation evidence; the organization-level override silently blanks that trail for every mailbox.'
    $mbxLearn = @(@{ label = 'Manage mailbox auditing'; url = 'https://learn.microsoft.com/en-us/purview/audit-mailboxes'; tag = 'docs' })
    if (-not $mbxKnown) {
        $findings.Add((New-PpaFinding -Id 'AUD-04' -DomId 'f-aud-4' -Title 'Mailbox auditing default not readable this session' -Status 'Verify manually' `
            -Whyline $whyMbx `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Mailbox auditing (organization default)', 'Not readable this session') -Status 'Verify manually'
            )) `
            -LearnMore $mbxLearn))
    }
    elseif ($mbxDisabled) {
        $findings.Add((New-PpaFinding -Id 'AUD-04' -DomId 'f-aud-4' -Title 'Mailbox auditing is disabled by organization override' -Status 'Improvement' `
            -Whyline $whyMbx `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Mailbox auditing (organization default)', 'Disabled (AuditDisabled = true)') -Status 'Improvement'
                New-PpaRow -Cells @('Per-mailbox bypass', 'Not assessed - organization default only') -Status 'Informational'
            )) `
            -LearnMore $mbxLearn))
    }
    else {
        $findings.Add((New-PpaFinding -Id 'AUD-04' -DomId 'f-aud-4' -Title 'Mailbox auditing is on by default' -Status 'OK' `
            -Whyline $whyMbx `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Mailbox auditing (organization default)', 'On (AuditDisabled = false)') -Status 'OK'
            )) `
            -LearnMore $mbxLearn))
    }

    # --- glance ---
    # Headline is OK only when logging is actually on. No tier claim without detection.
    # A confirmed mailbox-auditing override (AUD-04 Improvement) drags the pill to
    # Improvement; an unreadable org read (Verify manually) never does.
    $glance = if ($enabled -and $mbxKnown -and $mbxDisabled) {
        New-PpaGlance -Name 'Audit' -Status 'Improvement' -Metric 'On' -Sub 'mailbox auditing suppressed'
    }
    elseif ($enabled) {
        New-PpaGlance -Name 'Audit' -Status 'OK' -Metric 'On' -Sub 'unified audit logging'
    }
    elseif ($enabledKnown) {
        New-PpaGlance -Name 'Audit' -Metric 'Off' -Sub 'unified audit logging'
    }
    else {
        New-PpaGlance -Name 'Audit' -Metric 'Unknown' -Sub 'not readable this session'
    }

    return New-PpaSection -Id 'Audit' -Title 'Audit' -Group 'Discovery & Response' `
        -GroupIcon 'fas fa-search' -Glance $glance -Findings $findings.ToArray()
}
