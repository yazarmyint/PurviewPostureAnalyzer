# Invoke-PpaDspmAiAnalyzer.ps1 - analyzer for section 08 (DSPM for AI / Copilot).
# Evidence from Security & Compliance artifacts: DLP policies scoped to Microsoft 365
# Copilot (EnforcementPlanes=CopilotExperiences / Locations Workload=Applications with
# Copilot* locations - both VERIFIED 2026-07-02, docs/specs/ai-findings-build-spec.md).
# Severity policy (spec global rule 3): Copilot-experiences DLP is an E5-included feature,
# so its ABSENCE is a legitimate Recommendation; simulation mode is an Improvement.
# Pay-as-you-go / Agent 365 gated surfaces are only ever reported as Informational.
# ASCII-only source. Depends on New-PpaFinding/New-PpaSection/Get-PpaRequirement.

Set-StrictMode -Off

function New-PpaAiDegradedFinding {
    # Honest degradation for one AI sub-read (spec global rule 2):
    # - CommandNotFound -> Informational transparency note: the surface is not exposed to
    #   this session/tenant, so there is nothing to verify and no severity.
    # - AccessDenied / Error -> Verify manually; the remark carries the real reason (for
    #   AccessDenied, the note names the missing role when the caller provides one).
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$DomId,
        [Parameter(Mandatory = $true)][string]$Surface,
        [Parameter(Mandatory = $true)][string]$CollectorStatus,
        [string]$ErrorText,
        $LearnMore = @(),
        [string]$Requires,
        [string]$AccessDeniedNote
    )
    $params = @{ Id = $Id; DomId = $DomId; LearnMore = $LearnMore }
    if (-not [string]::IsNullOrEmpty($Requires)) { $params.Requires = $Requires }
    if ($CollectorStatus -eq 'CommandNotFound') {
        $params.Title   = "$Surface - surface not exposed to this session"
        $params.Status  = 'Informational'
        $params.Whyline = "The $Surface read surface is not exposed to this session or tenant, so there is nothing to assess - a transparency note, not a gap."
        $params.Table   = New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
            New-PpaRow -Cells @($Surface, 'Not exposed to this session / tenant') -Status 'Informational' -Remark $ErrorText)
    }
    else {
        $note = if ($CollectorStatus -eq 'AccessDenied' -and -not [string]::IsNullOrEmpty($AccessDeniedNote)) { $AccessDeniedNote } else { $ErrorText }
        $params.Title   = "$Surface not readable this session"
        $params.Status  = 'Verify manually'
        $params.Whyline = "$Surface could not be read this session, so this posture was not evaluated - confirm in the Purview portal."
        $params.Table   = New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
            New-PpaRow -Cells @($Surface, 'Not readable this session') -Status 'Verify manually' -Remark $note)
    }
    return New-PpaFinding @params
}

function Invoke-PpaDspmAiAnalyzer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Raw,
        # Parsed Data/license-requirements.json (static annotation map, not detection).
        $LicenseMap,
        # Whether any site/container-scoped sensitivity label exists (from the labels collector).
        [bool]$HasSiteLabels = $false
    )

    $mid = Get-PpaMidDot
    $dlpStatus  = [string]$Raw.copilotPolicies.status
    $policies   = @($Raw.copilotPolicies.items)
    $thirdParty = @($Raw.copilotPolicies.thirdPartyAiDlpPolicies | Where-Object { $_ })
    $findings = New-Object System.Collections.Generic.List[object]
    $lm01 = @(
        @{ label = 'Microsoft Purview portal - DSPM for AI'; url = 'https://purview.microsoft.com'; tag = 'portal' }
        @{ label = 'Data security for AI'; url = 'https://learn.microsoft.com/en-us/purview/ai-microsoft-purview'; tag = 'docs' }
    )

    # --- DLP read did not complete -> unknown is never asserted as empty. The section
    # still continues to AI-04+ below: each AI sub-read degrades independently (rule 2). ---
    $dlpReadable = ($dlpStatus -eq 'Ok')
    if (-not $dlpReadable) {
        $findings.Add((New-PpaFinding -Id 'AI-01' -DomId 'f-ai-1' -Title 'Copilot DLP posture not readable this session' -Status 'Verify manually' -Requires (Get-PpaRequirement $LicenseMap 'AI-01') `
            -Whyline 'DLP policies could not be enumerated this session, so Copilot data security posture was not evaluated - confirm in the Purview portal.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Copilot-scoped DLP policies', 'Not readable this session') -Status 'Verify manually' -Remark ([string]$Raw.copilotPolicies.error)
            )) -LearnMore $lm01))
    }

    # --- AI-01: AI surface, from S&C evidence ---
    if ($dlpReadable -and $policies.Count -gt 0) {
        $findings.Add((New-PpaFinding -Id 'AI-01' -DomId 'f-ai-1' -Title 'Copilot-scoped DLP artifacts present - AI surface in scope' -Status 'Informational' -Requires (Get-PpaRequirement $LicenseMap 'AI-01') `
            -Whyline 'DLP policies scoped to the Microsoft 365 Copilot location exist, which puts AI data security posture in scope for this tenant.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Copilot-scoped DLP policies', [string]$policies.Count) -Status 'Informational'
            )) -LearnMore $lm01))
    }
    elseif ($dlpReadable) {
        # No artifacts is NOT evidence that Copilot is absent - deployment is not
        # detectable read-only from the S&C session.
        $findings.Add((New-PpaFinding -Id 'AI-01' -DomId 'f-ai-1' -Title 'Copilot deployment not detectable from this session' -Status 'Informational' -Requires (Get-PpaRequirement $LicenseMap 'AI-01') `
            -Whyline 'No Copilot-scoped DLP artifacts were found, and Copilot deployment itself is not readable from the Security & Compliance session. If Copilot is deployed, DSPM for AI applies.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Copilot-scoped DLP policies', '0') -Status 'Informational'
                New-PpaRow -Cells @('Microsoft 365 Copilot deployment', 'Not detectable read-only') -Status 'Verify manually' -Remark 'confirm Copilot deployment with the client; if deployed, configure DSPM for AI (Purview portal) and re-run.'
            )) -LearnMore $lm01))
    }

    # --- AI-02: Copilot DLP posture (absence / simulation / enforcing - spec F2) ---
    $lm02 = @(
        @{ label = 'Data Security Posture Management for AI'; url = 'https://learn.microsoft.com/en-us/purview/dspm-for-ai'; tag = 'docs' }
        @{ label = 'DLP for Microsoft 365 Copilot and Copilot Chat'; url = 'https://learn.microsoft.com/en-us/purview/dlp-microsoft365-copilot-location-learn-about'; tag = 'docs' }
    )
    # A row reported factually when the [UNVERIFIED] third-party AI app DLP carriers are
    # populated on ANY policy; silent when empty (above-E5 rule - no meaning asserted).
    $tpRemark = 'Reported factually - third-party AI app scoping is a pay-as-you-go / Agent 365 gated surface and its meaning is not asserted from cmdlet output.'
    if (-not $dlpReadable) {
        # No AI-02/AI-03 verdicts from a failed read - AI-01 above carries the Verify.
    }
    elseif ($policies.Count -eq 0) {
        $rows02 = New-Object System.Collections.Generic.List[object]
        $rows02.Add((New-PpaRow -Cells @('Copilot-targeting DLP policies', '0') -Status 'Recommendation'))
        if ($thirdParty.Count -gt 0) {
            $rows02.Add((New-PpaRow -Cells @('Third-party app DLP locations configured', ($thirdParty -join ', ')) -Status 'Informational' -Remark $tpRemark))
        }
        $findings.Add((New-PpaFinding -Id 'AI-02' -DomId 'f-ai-2' -Title 'Copilot interactions not governed by DLP' -Status 'Recommendation' -Requires (Get-PpaRequirement $LicenseMap 'AI-02') `
            -Whyline 'Microsoft 365 Copilot interactions are not governed by any DLP policy - prompts and responses carry no data security control.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows $rows02.ToArray()) -LearnMore $lm02))
    }
    else {
        $enforcing = @($policies | Where-Object { [string]$_.mode -match '(?i)^enable$|enforce' })
        $offModes  = @($policies | Where-Object { [string]$_.mode -notmatch '(?i)^enable$|enforce' } | ForEach-Object { [string]$_.mode } | Select-Object -Unique)
        $status02 = if ($enforcing.Count -eq $policies.Count) { 'OK' } else { 'Improvement' }
        $title02  = if ($status02 -eq 'OK') { 'Copilot DLP policy is enforcing' } else { 'Copilot DLP coverage in simulation mode - not enforced' }
        $why02    = if ($status02 -eq 'OK') { 'Copilot-scoped DLP coverage is active and enforcing.' }
                    else { "Copilot DLP coverage exists but is in simulation mode ($($offModes -join ', ')) - interactions are not being enforced. Review simulation results and enable when tuned." }
        $rows02 = New-Object System.Collections.Generic.List[object]
        foreach ($p in $policies) {
            $isEnf = [string]$p.mode -match '(?i)^enable$|enforce'
            $remarkParts = New-Object System.Collections.Generic.List[string]
            if (@($p.copilotLocations).Count -gt 0) { [void]$remarkParts.Add('Copilot locations: ' + (@($p.copilotLocations) -join ', ') + '.') }
            if ($p.oneClick) { [void]$remarkParts.Add('Microsoft-deployed one-click default (fingerprint match).') }
            if ($p.parseFallback) { [void]$remarkParts.Add('Locations parsed via text fallback - reduced confidence.') }
            # New-PpaRow drops a null/empty Remark, so passing it unconditionally is safe.
            $remark = if ($remarkParts.Count -gt 0) { $remarkParts -join ' ' } else { $null }
            $rows02.Add((New-PpaRow -Cells @($p.name, (@($p.sits) -join ', '), [string]$p.mode, [string]$p.created) -Status ($(if ($isEnf) { 'OK' } else { 'Improvement' })) -Remark $remark))
        }
        if ($thirdParty.Count -gt 0) {
            $rows02.Add((New-PpaRow -Cells @('Third-party app DLP locations configured', ($thirdParty -join ', '), '', '') -Status 'Informational' -Remark $tpRemark))
        }
        $findings.Add((New-PpaFinding -Id 'AI-02' -DomId 'f-ai-2' -Title $title02 -Status $status02 -Requires (Get-PpaRequirement $LicenseMap 'AI-02') `
            -Whyline $why02 `
            -Table (New-PpaTable -Columns @('AI Policy', 'Conditions', 'Mode', 'Created', 'Status') -Rows $rows02.ToArray()) -LearnMore $lm02))
    }

    # --- AI-03: label-based Copilot content exclusion (the oversharing control itself) ---
    # Evidence from the Copilot-location rules: does any rule use a 'Content contains ->
    # Sensitivity labels' condition (restrict Copilot from processing labeled content)?
    # Only assessable when Copilot-scoped policies exist to carry such rules.
    if ($policies.Count -gt 0) {
        $labelRules = @($policies | Where-Object { $_.hasLabelCondition })
        $labelNames = @($policies | ForEach-Object { $_.labelRefs } | Where-Object { $_ } | Select-Object -Unique)
        $status03 = if ($labelRules.Count -gt 0) { 'OK' } else { 'Recommendation' }
        $title03  = if ($labelRules.Count -gt 0) { 'Label-based Copilot content exclusion configured' } else { 'No label-based Copilot content exclusion' }
        $ruleSetting = if ($labelRules.Count -gt 0) {
            if ($labelNames.Count -gt 0) { "$($labelRules.Count) policies $mid labels: " + ($labelNames -join ', ') } else { "$($labelRules.Count) policies" }
        } else { 'None detected' }
        $rows03 = @(
            New-PpaRow -Cells @('Copilot-location rules referencing sensitivity labels', $ruleSetting) -Status $status03
            New-PpaRow -Cells @('Container/site-scoped sensitivity labels defined', ($(if ($HasSiteLabels) { 'Yes' } else { 'No' }))) -Status 'Informational'
        )
        $findings.Add((New-PpaFinding -Id 'AI-03' -DomId 'f-ai-3' -Title $title03 -Status $status03 `
            -Whyline "Without label-based exclusion, Copilot can process and surface labeled content users can technically open but shouldn't - oversharing risk." `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows $rows03) `
            -LearnMore @(
                @{ label = 'DLP for Microsoft 365 Copilot and Copilot Chat'; url = 'https://learn.microsoft.com/en-us/purview/dlp-microsoft365-copilot-location-learn-about'; tag = 'docs' }
                @{ label = 'Considerations for Copilot & oversharing'; url = 'https://learn.microsoft.com/en-us/purview/ai-microsoft-purview-considerations'; tag = 'docs' })))
    }

    # --- AI-04: DSPM collection policies (spec F1; PAYG / Agent 365 gated surface) ---
    # Skipped entirely when the raw shape predates this sub-read (older captures).
    if ($null -ne $Raw.dspmPolicies) {
        $lm04 = @(@{ label = 'Retention and AI app locations (prerequisites)'; url = 'https://learn.microsoft.com/en-us/purview/create-retention-policies'; tag = 'docs' })
        $dspmStatus = [string]$Raw.dspmPolicies.status
        if ($dspmStatus -eq 'Ok') {
            $dspmItems = @($Raw.dspmPolicies.items | Where-Object { $null -ne $_ })
            if ($dspmItems.Count -gt 0) {
                # Object schema is UNKNOWN (0 objects in the verified sandbox) - render every
                # property name/value pair the collector captured, dynamically.
                $rows04 = New-Object System.Collections.Generic.List[object]
                foreach ($it in $dspmItems) {
                    $label = if ([string]::IsNullOrEmpty([string]$it.name)) { '(unnamed policy)' } else { [string]$it.name }
                    $first = $true
                    foreach ($pr in @($it.props)) {
                        $rows04.Add((New-PpaRow -Cells @($(if ($first) { $label } else { '' }), [string]$pr.n, [string]$pr.v) -Status 'Informational' -Indent:(-not $first)))
                        $first = $false
                    }
                    if ($first) { $rows04.Add((New-PpaRow -Cells @($label, '', '') -Status 'Informational')) }
                }
                $findings.Add((New-PpaFinding -Id 'AI-04' -DomId 'f-ai-4' -Title "DSPM collection policies configured: $($dspmItems.Count)" -Status 'Informational' `
                    -Whyline 'Collection policies govern interaction capture for Enterprise AI apps and Other AI apps (pay-as-you-go / Agent 365 surfaces) and are a prerequisite for governing AI apps other than Microsoft 365 Copilot and Copilot Studio.' `
                    -Table (New-PpaTable -Columns @('Collection Policy', 'Property', 'Value', 'Status') -Rows $rows04.ToArray()) -LearnMore $lm04))
            }
            else {
                # Above-E5 rule: absence of a PAYG/Agent 365 feature is Informational, never a gap.
                $findings.Add((New-PpaFinding -Id 'AI-04' -DomId 'f-ai-4' -Title 'No DSPM collection policies detected' -Status 'Informational' `
                    -Whyline 'Collection policies govern interaction capture for Enterprise AI apps and Other AI apps and require pay-as-you-go billing or Agent 365 licensing; applicable only if licensed. They are a prerequisite for governing AI apps other than Microsoft 365 Copilot and Copilot Studio.' `
                    -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                        New-PpaRow -Cells @('DSPM collection policies', '0') -Status 'Informational'
                    )) -LearnMore $lm04))
            }
        }
        else {
            $findings.Add((New-PpaAiDegradedFinding -Id 'AI-04' -DomId 'f-ai-4' -Surface 'DSPM collection policies (Get-DspmPolicy)' `
                -CollectorStatus $dspmStatus -ErrorText ([string]$Raw.dspmPolicies.error) -LearnMore $lm04))
        }
    }

    # --- AI-05: Copilot / AI-app retention coverage (spec F3) ---
    # Skipped entirely when the raw shape predates this sub-read (older captures).
    if ($null -ne $Raw.appRetention) {
        $lm05 = @(
            @{ label = 'Retention cmdlets (older vs newer locations)'; url = 'https://learn.microsoft.com/en-us/purview/retention-cmdlets'; tag = 'docs' }
            @{ label = 'Create and configure retention policies'; url = 'https://learn.microsoft.com/en-us/purview/create-retention-policies'; tag = 'docs' }
        )
        $appStatus = [string]$Raw.appRetention.status
        if ($appStatus -ne 'Ok') {
            $findings.Add((New-PpaAiDegradedFinding -Id 'AI-05' -DomId 'f-ai-5' -Surface 'Copilot / AI app retention (Get-AppRetentionCompliancePolicy)' `
                -CollectorStatus $appStatus -ErrorText ([string]$Raw.appRetention.error) -LearnMore $lm05))
        }
        else {
            $appItems     = @($Raw.appRetention.items | Where-Object { $null -ne $_ })
            $covering     = @($appItems | Where-Object { $_.copilotCovered })
            $noAppsShape  = @($appItems | Where-Object { -not $_.hasApplications })
            $otherTokens  = @($appItems | ForEach-Object { $_.applications } | Where-Object { $_ -and ($_ -notmatch '(?i)teams|yammer|viva|copilot') } | Select-Object -Unique)
            $legacyOk     = ([string]$Raw.retentionLegacy.status -eq 'Ok')
            $legacyTeams  = @($Raw.retentionLegacy.teamsChatPolicies | Where-Object { $_ })
            $classicTotal = if ($legacyOk) { [int]$Raw.retentionLegacy.totalCount } else { 0 }

            $rows05 = New-Object System.Collections.Generic.List[object]
            if ($covering.Count -gt 0) {
                $status05 = 'OK'
                $title05  = 'Copilot interaction data covered by retention'
                $why05    = 'A policy in the App retention family covers Microsoft Copilot experiences, giving Copilot interaction data a retain/delete lifecycle.'
                foreach ($p in $covering) {
                    $setting = (@($p.applications) -join ', ')
                    if (-not [string]::IsNullOrEmpty([string]$p.enabled)) { $setting = "$setting (Enabled: $($p.enabled))" }
                    $rows05.Add((New-PpaRow -Cells @([string]$p.name, $setting) -Status 'OK'))
                }
            }
            elseif ($noAppsShape.Count -gt 0) {
                # [carrier VERIFIED live: 'Users:M365Copilot' (Wave 5 cleanup Part 1)] this
                # branch stays for tenants where policies exist but the Applications property
                # is absent/shaped differently - coverage there is genuinely un-assertable.
                $status05 = 'Verify manually'
                $title05  = 'Copilot retention coverage not assertable this session'
                $why05    = 'App retention policies exist, but Copilot retention coverage is not assertable from cmdlet output on this tenant - confirm the policy locations in the Purview portal.'
                foreach ($p in $appItems) {
                    $rows05.Add((New-PpaRow -Cells @([string]$p.name, $(if ([string]::IsNullOrEmpty([string]$p.enabled)) { '' } else { "Enabled: $($p.enabled)" })) -Status 'Verify manually'))
                }
            }
            elseif ($appItems.Count -eq 0 -and $legacyOk -and $classicTotal -eq 0) {
                # Sparse-tenant regression case: zero retention policies of any kind renders
                # as a clean Recommendation (E5-included feature), never a crash or blank.
                $status05 = 'Recommendation'
                $title05  = 'No retention lifecycle for Copilot interactions'
                $why05    = 'No retention policies exist tenant-wide, so Copilot interaction data has no retention/deletion lifecycle policy.'
                $rows05.Add((New-PpaRow -Cells @('Copilot-experiences retention coverage', 'None detected') -Status 'Recommendation'))
            }
            else {
                $status05 = 'Improvement'
                $title05  = 'Copilot interaction data has no retention lifecycle'
                $why05    = 'Retention exists in the tenant, but no policy covers Microsoft Copilot experiences - Copilot interaction data has no retention/deletion lifecycle policy.'
                $rows05.Add((New-PpaRow -Cells @('Copilot-experiences retention coverage', 'None detected') -Status 'Improvement'))
            }

            if ($legacyTeams.Count -gt 0) {
                $rows05.Add((New-PpaRow -Cells @('Legacy combined Teams/Copilot-era policies', ($legacyTeams -join ', ')) -Status 'Informational' `
                    -Remark 'TeamsChatLocation is populated - this may be the pre-split combined "Teams chats and Copilot interactions" location. Copilot coverage is not asserted from this legacy shape.'))
            }
            if ($otherTokens.Count -gt 0) {
                # [UNVERIFIED] exact tokens for Enterprise / Other AI apps - report verbatim.
                $rows05.Add((New-PpaRow -Cells @('Other AI app retention tokens (verbatim)', ($otherTokens -join ', ')) -Status 'Informational' `
                    -Remark 'Reported verbatim - the exact Applications tokens for Enterprise AI apps / Other AI apps are not yet documented.'))
            }
            else {
                $rows05.Add((New-PpaRow -Cells @('Enterprise / Other AI app retention locations', 'None detected') -Status 'Informational' `
                    -Remark 'Enterprise AI apps and Other AI apps retention locations require pay-as-you-go billing or Agent 365 licensing; applicable only if licensed.'))
            }

            $findings.Add((New-PpaFinding -Id 'AI-05' -DomId 'f-ai-5' -Title $title05 -Status $status05 `
                -Whyline $why05 `
                -Table (New-PpaTable -Columns @('Configuration / Policy', 'Setting', 'Status') -Rows $rows05.ToArray()) -LearnMore $lm05))
        }
    }

    # --- AI-06: Communication Compliance Copilot monitoring (spec F4, VERIFIED) ---
    # Skipped entirely when the raw shape predates this sub-read (older captures).
    if ($null -ne $Raw.ccCopilot) {
        $lm06 = @(@{ label = 'Communication Compliance for generative AI'; url = 'https://learn.microsoft.com/en-us/purview/communication-compliance-copilot'; tag = 'docs' })
        $req06 = Get-PpaRequirement $LicenseMap 'AI-06'
        $ccRoleNote = 'Communication Compliance objects require membership in a Communication Compliance role group; not readable with the roles used for this run.'
        # The IRM cross-reference (spec rule 7): risky-AI scoring renders in the IRM section.
        $irmXrefRow = New-PpaRow -Cells @('Insider Risk risky-AI coverage', 'Assessed in the Insider Risk Management section (IRM-03)', '') -Status 'Informational'
        $ccPolStatus  = [string]$Raw.ccCopilot.policiesStatus
        $ccRuleStatus = [string]$Raw.ccCopilot.rulesStatus
        if ($ccPolStatus -ne 'Ok' -or $ccRuleStatus -ne 'Ok') {
            # Degrade on EITHER cmdlet failing (scoping needs the rule read too).
            $badStatus = if ($ccPolStatus -ne 'Ok') { $ccPolStatus } else { $ccRuleStatus }
            $badError  = if ($ccPolStatus -ne 'Ok') { [string]$Raw.ccCopilot.policiesError } else { [string]$Raw.ccCopilot.rulesError }
            $findings.Add((New-PpaAiDegradedFinding -Id 'AI-06' -DomId 'f-ai-6' -Surface 'Communication Compliance Copilot monitoring' `
                -CollectorStatus $badStatus -ErrorText $badError -LearnMore $lm06 -Requires $req06 -AccessDeniedNote $ccRoleNote))
        }
        else {
            $ccItems = @($Raw.ccCopilot.items | Where-Object { $null -ne $_ })
            $ccCopilotScoped = @($ccItems | Where-Object { @($_.workloads) -match '(?i)^Copilot$' })
            $rows06 = New-Object System.Collections.Generic.List[object]
            if ($ccCopilotScoped.Count -eq 0) {
                $status06 = 'Recommendation'
                $title06  = 'AI prompts and responses not monitored by Communication Compliance'
                $why06    = "AI prompts and responses are not monitored by Communication Compliance. The 'Detect Microsoft 365 Copilot interactions' template provides a one-step baseline."
                $rows06.Add((New-PpaRow -Cells @('Copilot-scoped Communication Compliance policies', '0', '') -Status 'Recommendation'))
            }
            else {
                $enabledScoped = @($ccCopilotScoped | Where-Object { [string]$_.enabled -match '(?i)^true$' })
                $status06 = if ($enabledScoped.Count -gt 0) { 'OK' } else { 'Improvement' }
                $title06  = if ($status06 -eq 'OK') { 'Copilot interactions monitored by Communication Compliance' } else { 'Copilot Communication Compliance policy is disabled' }
                $why06    = if ($status06 -eq 'OK') { 'A Communication Compliance policy scopes the Copilot workload - AI prompts and responses are captured for review.' }
                            else { 'A Copilot-scoped Communication Compliance policy exists but is disabled - AI prompts and responses are not being captured.' }
                foreach ($p in $ccCopilotScoped) {
                    $remark = if ($p.parseFallback) { 'ContentSources parsed via text fallback - reduced confidence.' } else { $null }
                    $rows06.Add((New-PpaRow -Cells @([string]$p.name, [string]$p.enabled, (@($p.workloads) -join ', ')) -Status ($(if ([string]$p.enabled -match '(?i)^true$') { 'OK' } else { 'Improvement' })) -Remark $remark))
                }
            }
            # PAYG-gated channels: non-null -> factual Informational rows; null -> silent.
            $genAi = @($ccItems | Where-Object { $null -ne $_.unifiedGenAI } | ForEach-Object { "$($_.name): $($_.unifiedGenAI)" })
            if ($genAi.Count -gt 0) {
                $rows06.Add((New-PpaRow -Cells @('Unified GenAI workloads (PAYG-gated)', ($genAi -join ' ; '), '') -Status 'Informational'))
            }
            $tp06 = @($ccItems | Where-Object { $null -ne $_.thirdParty } | ForEach-Object { "$($_.name): $($_.thirdParty)" })
            if ($tp06.Count -gt 0) {
                $rows06.Add((New-PpaRow -Cells @('Third-party workloads (PAYG-gated)', ($tp06 -join ' ; '), '') -Status 'Informational'))
            }
            $rows06.Add($irmXrefRow)
            $findings.Add((New-PpaFinding -Id 'AI-06' -DomId 'f-ai-6' -Title $title06 -Status $status06 -Requires $req06 `
                -Whyline $why06 `
                -Table (New-PpaTable -Columns @('CC Policy / Configuration', 'Enabled / Setting', 'Workloads', 'Status') -Rows $rows06.ToArray()) -LearnMore $lm06))
        }
    }

    # --- glance ---
    $noun = if ($policies.Count -eq 1) { 'policy' } else { 'policies' }
    if (-not $dlpReadable) {
        $glance = New-PpaGlance -Name 'DSPM for AI' -Metric 'not readable' -Sub 'confirm in portal'
    }
    elseif ($policies.Count -eq 0) {
        $glance = New-PpaGlance -Name 'DSPM for AI' -Metric '0 policies' -Sub "AI surface $mid not detected"
    }
    else {
        $enforcingG = @($policies | Where-Object { [string]$_.mode -match '(?i)^enable$|enforce' })
        $modeState = if ($enforcingG.Count -eq $policies.Count) { 'enforcing' } else { 'audit only' }
        $glance = New-PpaGlance -Name 'DSPM for AI' -Metric "$($policies.Count) $noun" -Sub "$modeState $mid AI in scope"
    }

    return New-PpaSection -Id 'DSPM_for_AI' -Title 'DSPM for AI - Copilot Data Security' -Group 'AI Security' `
        -GroupIcon 'fas fa-robot' -GroupTag 'NEW' -Glance $glance -Findings $findings.ToArray()
}
