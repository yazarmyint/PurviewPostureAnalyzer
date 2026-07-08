# Get-PpaDspmAi.ps1 - collector for section 08 (DSPM for AI / Copilot Data Security).
# Reads Get-DlpCompliancePolicy and keeps the Microsoft 365 Copilot-scoped policies.
# Everything here is readable over Connect-IPPSSession. SIT NAMES only, no content.
# Detection keys verified against a live sandbox tenant 2026-07-02 (docs/specs/
# ai-findings-build-spec.md): EnforcementPlanes containing CopilotExperiences, and the
# Locations JSON string carrying Workload=Applications entries with Copilot* locations
# (observed: Copilot.M365). Policy NAME is corroboration only - names are admin-editable
# and never flag a policy on their own.
# ASCII-only source. Depends on Invoke-PpaReadCmdlet.ps1.

Set-StrictMode -Off

# The Microsoft 365 Copilot DLP location id, from the New-DlpCompliancePolicy reference:
#   Locations [{"Workload":"Applications","Location":"470f2276-...","Inclusions":...}]
#   -EnforcementPlanes @("CopilotExperiences")
$script:PpaCopilotLocationGuid = '470f2276-e011-4e9d-a6ec-20768be3a4b0'

function ConvertFrom-PpaJsonText {
    # Parse a JSON-serialized string property (global rule 4 of the AI findings spec).
    # Returns the parsed object, or $null on any parse failure - the caller then falls
    # back to regex containment on the raw string and flags reduced confidence.
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try { return ($Text | ConvertFrom-Json -ErrorAction Stop) }
    catch { return $null }
}

function Get-PpaCopilotDlpSignals {
    # Detection detail for one DLP policy, in the spec's priority order.
    # Returns: isCopilot, copilotLocations[], parseFallback (Locations JSON did not parse
    # and regex fallback was used), oneClick (Microsoft-deployed one-click default
    # fingerprint - informational tag, never a severity input).
    param($Policy)

    $isCopilot     = $false
    $locations     = New-Object System.Collections.Generic.List[string]
    $parseFallback = $false
    $purviewConfig = $false

    # 1) [VERIFIED] EnforcementPlanes contains CopilotExperiences (string or array).
    if ($Policy.PSObject.Properties.Name -contains 'EnforcementPlanes') {
        if ((($Policy.EnforcementPlanes | Out-String)) -match '(?i)CopilotExperiences') { $isCopilot = $true }
    }

    # 2) [VERIFIED] Locations JSON string: Workload=Applications, Location like Copilot*
    #    (observed Copilot.M365; other Copilot-family values are reported as found, not
    #    matched against a fixed list). LocationSource=PurviewConfig feeds the one-click
    #    fingerprint.
    if ($Policy.PSObject.Properties.Name -contains 'Locations' -and -not [string]::IsNullOrEmpty([string]$Policy.Locations)) {
        $locRaw = [string]$Policy.Locations
        $parsed = ConvertFrom-PpaJsonText $locRaw
        if ($null -ne $parsed) {
            foreach ($entry in @($parsed)) {
                if (([string]$entry.Workload) -eq 'Applications' -and ([string]$entry.Location) -match '(?i)^Copilot') {
                    $isCopilot = $true
                    [void]$locations.Add([string]$entry.Location)
                }
                if (([string]$entry.LocationSource) -match '(?i)PurviewConfig') { $purviewConfig = $true }
            }
        }
        else {
            # Parse failure -> regex containment on the raw string, reduced confidence.
            if ($locRaw -match '(?i)"Workload"\s*:\s*"Applications"' -and $locRaw -match '(?i)"Location"\s*:\s*"Copilot[^"]*"') {
                $isCopilot = $true
                $parseFallback = $true
                foreach ($m in [regex]::Matches($locRaw, '(?i)"Location"\s*:\s*"(Copilot[^"]*)"')) { [void]$locations.Add($m.Groups[1].Value) }
            }
            if ($locRaw -match '(?i)PurviewConfig') { $purviewConfig = $true }
        }
        # The documented Copilot location GUID remains a corroborating structural signal.
        if ($locRaw -match [regex]::Escape($script:PpaCopilotLocationGuid)) { $isCopilot = $true }
    }

    # 3) Other explicit Copilot location properties (unverified shapes, null-safe).
    foreach ($prop in @('CopilotLocation', 'Microsoft365CopilotLocation')) {
        if ($Policy.PSObject.Properties.Name -contains $prop) {
            if (([string]$Policy.$prop) -match '(?i)copilot') { $isCopilot = $true }
        }
    }
    # Policy NAME (dspm|copilot|AI) is deliberately NOT a detection signal on its own -
    # it only corroborates in the analyzer's drill-down copy.

    # One-click artifact fingerprint [VERIFIED]: name prefix, comment opening, and
    # LocationSource=PurviewConfig. Two of three suffices (tolerates admin edits).
    $fpName    = ([string]$Policy.Name) -like 'Default DLP policy - *'
    $fpComment = $false
    if ($Policy.PSObject.Properties.Name -contains 'Comment') {
        $fpComment = ([string]$Policy.Comment) -match '(?i)^Prevent data leakage and oversharing by restricting\s+Microsoft 365 Copilot'
    }
    $fpScore = @($fpName, $fpComment, $purviewConfig | Where-Object { $_ }).Count
    $oneClick = ($fpScore -ge 2)

    return [pscustomobject]@{
        isCopilot       = $isCopilot
        copilotLocations = @($locations | Select-Object -Unique)
        parseFallback   = $parseFallback
        oneClick        = $oneClick
    }
}

function Get-PpaRuleLabelReferences {
    # Best-effort: sensitivity-label NAMES referenced by a DLP rule's conditions - the
    # signal behind label-based Copilot content exclusion ('Content contains -> Sensitivity
    # labels'). Labels appear as label groups (type 'Sensitivity') inside
    # ContentContainsSensitiveInformation, or inside the AdvancedRule JSON.
    # CONFIRM against a live tenant: rule condition shapes vary by how the policy was built.
    param($Rule)
    $names = New-Object System.Collections.Generic.List[string]
    # Walk ContentContainsSensitiveInformation: groups -> labels (type Sensitivity).
    foreach ($entry in @($Rule.ContentContainsSensitiveInformation)) {
        foreach ($grp in @($entry.groups)) {
            foreach ($lab in @($grp.labels)) {
                if (([string]$lab.type) -match '(?i)sensitivity' -and $lab.name) { [void]$names.Add([string]$lab.name) }
            }
        }
        # Flat shape: the entry itself may be a label reference.
        if (([string]$entry.type) -match '(?i)sensitivity' -and $entry.name) { [void]$names.Add([string]$entry.name) }
    }
    $hasLabelCondition = ($names.Count -gt 0)
    # Fallback: AdvancedRule JSON text mentions a Sensitivity-typed label condition.
    if (-not $hasLabelCondition -and ($Rule.PSObject.Properties.Name -contains 'AdvancedRule')) {
        if (([string]$Rule.AdvancedRule) -match '"type"\s*:\s*"Sensitivity"') { $hasLabelCondition = $true }
    }
    return [pscustomobject]@{ hasLabelCondition = $hasLabelCondition; labelNames = @($names | Select-Object -Unique) }
}

function Get-PpaDspmPolicyItems {
    # Schema-defensive projection of Get-DspmPolicy objects. The cmdlet family is
    # VERIFIED present and readable with Compliance-Reader-tier roles (2026-07-02), but it
    # returned 0 objects in the sandbox, so the object schema is UNKNOWN. Capture Name if
    # present plus every property name/value pair generically; never bind to specific
    # property names beyond Name. (Import-DlpComplianceRuleCollection matched the probe's
    # 'collection' keyword but is legacy DLP rule-collection import tooling - ignored.)
    param($Data)
    $items = New-Object System.Collections.Generic.List[object]
    $artifactNames = Get-PpaSessionArtifactNames
    foreach ($o in @($Data)) {
        if ($null -eq $o) { continue }
        $name = ''
        if ($o.PSObject.Properties.Name -contains 'Name') { $name = [string]$o.Name }
        $props = New-Object System.Collections.Generic.List[object]
        foreach ($pr in $o.PSObject.Properties) {
            # Generic projection: remoting session artifacts must not survive (A.3).
            if ($artifactNames -contains $pr.Name) { continue }
            # Guid is projected as the top-level guid identity field (A.5); keeping it
            # in the bag would double-report identity in delta (ruled at Part C review).
            if ($pr.Name -eq 'Guid') { continue }
            $v = ''
            if ($null -ne $pr.Value) { $v = ("" + ($pr.Value | Out-String)).Trim() }
            if ($v.Length -gt 120) { $v = $v.Substring(0, 117) + '...' }
            $props.Add([pscustomobject]@{ n = [string]$pr.Name; v = $v })
        }
        $items.Add([pscustomobject]@{ name = $name; guid = Get-PpaOptionalGuid $o; props = $props.ToArray() })
    }
    return $items.ToArray()
}

function Get-PpaAppRetentionItems {
    # Projection of Get-AppRetentionCompliancePolicy - the modern AI retention locations
    # ("Microsoft Copilot experiences", "Enterprise AI apps", "Other AI apps") live in the
    # App retention family. [VERIFIED 2026-07, Wave 5 cleanup Part 1] the carrier property
    # is 'Applications'; the observed Copilot token is 'Users:M365Copilot' (plural 'Users:',
    # not the doc-grounded 'User:' singular - the M365Copilot containment match below covers
    # both). Each item still records whether the property was present at all - absent/odd
    # shapes degrade to a not-assertable transparency line in the analyzer, never a false
    # absence.
    param($Data)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($Data)) {
        if ($null -eq $p) { continue }
        $hasApplications = ($p.PSObject.Properties.Name -contains 'Applications')
        $apps = @()
        if ($hasApplications) { $apps = @($p.Applications | Where-Object { $_ } | ForEach-Object { [string]$_ }) }
        $enabled = ''
        if ($p.PSObject.Properties.Name -contains 'Enabled') { $enabled = [string]$p.Enabled }
        $items.Add([pscustomobject]@{
            name            = [string]$p.Name
            guid            = Get-PpaOptionalGuid $p
            enabled         = $enabled
            hasApplications = $hasApplications
            applications    = $apps
            copilotCovered  = (@($apps -match '(?i)M365Copilot').Count -gt 0)
        })
    }
    return $items.ToArray()
}

function Get-PpaCcCopilotItems {
    # Communication Compliance Copilot scoping (spec F4, VERIFIED end to end 2026-07-02).
    # Scoping lives on the RULE, not the policy - the policy-level Locations property was
    # observed empty even for a Copilot-scoped policy. ContentSources on the rule is a JSON
    # string; observed shape: {"RevieweeName":"AllUsersGroupsOfTenant", ...,
    # "Workloads":["Copilot"], "ThirdPartyWorkloads":null, "UnifiedGenAIWorkloads":null}.
    # Rule->policy association: the rule's policy reference property when present, else
    # Name equality (VERIFIED: the template-created pair shares the name
    # "Microsoft 365 Copilot interactions").
    param($Policies, $Rules)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($Policies)) {
        if ($null -eq $p) { continue }
        $rule = $null
        foreach ($r in @($Rules)) {
            if ($null -eq $r) { continue }
            $assoc = $false
            foreach ($prop in @('Policy', 'PolicyId', 'ParentPolicyName')) {
                if ($r.PSObject.Properties.Name -contains $prop -and $r.$prop) {
                    $ref = [string]$r.$prop
                    if ($ref -eq [string]$p.Name -or ($p.PSObject.Properties.Name -contains 'Guid' -and $ref -eq [string]$p.Guid)) { $assoc = $true; break }
                }
            }
            if (-not $assoc -and ([string]$r.Name) -eq ([string]$p.Name)) { $assoc = $true }
            if ($assoc) { $rule = $r; break }
        }

        $workloads = New-Object System.Collections.Generic.List[string]
        $unified = $null; $thirdP = $null; $parseFallback = $false
        if ($null -ne $rule -and $rule.PSObject.Properties.Name -contains 'ContentSources' -and -not [string]::IsNullOrEmpty([string]$rule.ContentSources)) {
            $csRaw = [string]$rule.ContentSources
            $parsed = ConvertFrom-PpaJsonText $csRaw
            if ($null -ne $parsed) {
                foreach ($entry in @($parsed)) {
                    foreach ($w in @($entry.Workloads | Where-Object { $_ })) { [void]$workloads.Add([string]$w) }
                    if ($null -ne $entry.UnifiedGenAIWorkloads) { $unified = (@($entry.UnifiedGenAIWorkloads | Where-Object { $_ }) -join ', ') }
                    if ($null -ne $entry.ThirdPartyWorkloads)   { $thirdP  = (@($entry.ThirdPartyWorkloads | Where-Object { $_ }) -join ', ') }
                }
            }
            else {
                # Parse failure -> regex containment on the raw string, reduced confidence.
                $parseFallback = $true
                if ($csRaw -match '(?i)"Workloads"\s*:\s*\[[^\]]*"Copilot"') { [void]$workloads.Add('Copilot') }
                if ($csRaw -match '(?i)"UnifiedGenAIWorkloads"\s*:\s*(?!null)\S') { $unified = '(present - unparsed)' }
                if ($csRaw -match '(?i)"ThirdPartyWorkloads"\s*:\s*(?!null)\S')   { $thirdP  = '(present - unparsed)' }
            }
        }

        $enabled = ''
        if ($p.PSObject.Properties.Name -contains 'Enabled') { $enabled = [string]$p.Enabled }
        $items.Add([pscustomobject]@{
            name          = [string]$p.Name
            guid          = Get-PpaOptionalGuid $p
            enabled       = $enabled
            workloads     = @($workloads | Select-Object -Unique)
            unifiedGenAI  = $unified
            thirdParty    = $thirdP
            parseFallback = $parseFallback
            hasRule       = ($null -ne $rule)
        })
    }
    return $items.ToArray()
}

function Get-PpaDspmAi {
    [CmdletBinding()]
    param()

    $rawPols    = Invoke-PpaReadCmdlet -Name 'Get-DlpCompliancePolicy'
    $rawRules   = Invoke-PpaReadCmdlet -Name 'Get-DlpComplianceRule'
    $rawDspm    = Invoke-PpaReadCmdlet -Name 'Get-DspmPolicy'
    $rawAppRet  = Invoke-PpaReadCmdlet -Name 'Get-AppRetentionCompliancePolicy'
    $rawRet     = Invoke-PpaReadCmdlet -Name 'Get-RetentionCompliancePolicy'
    $rawCcPols  = Invoke-PpaReadCmdlet -Name 'Get-SupervisoryReviewPolicyV2'
    $rawCcRules = Invoke-PpaReadCmdlet -Name 'Get-SupervisoryReviewRule'

    $items = New-Object System.Collections.Generic.List[object]
    $thirdPartyAiDlp = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($rawPols.Data)) {
        # [UNVERIFIED] probable carriers for non-Copilot AI app DLP scoping - reported
        # factually when populated on ANY policy, silent when empty (above-E5 rule).
        foreach ($prop in @('ThirdPartyAppDlpLocation', 'ThirdPartyAppDlpLocationException')) {
            if ($p.PSObject.Properties.Name -contains $prop -and @($p.$prop | Where-Object { $_ }).Count -gt 0) {
                [void]$thirdPartyAiDlp.Add([string]$p.Name)
                break
            }
        }

        $signals = Get-PpaCopilotDlpSignals $p
        if (-not $signals.isCopilot) { continue }
        $rules = @($rawRules.Data | Where-Object { $_.ParentPolicyName -eq $p.Name -or $_.Policy -eq $p.Guid })
        $sits = @($rules | ForEach-Object { $_.ContentContainsSensitiveInformation } | ForEach-Object { $_.Name } | Where-Object { $_ } | ForEach-Object { [string]$_ } | Select-Object -Unique)
        $labelNames = New-Object System.Collections.Generic.List[string]
        $hasLabelCondition = $false
        foreach ($r in $rules) {
            $ref = Get-PpaRuleLabelReferences $r
            if ($ref.hasLabelCondition) { $hasLabelCondition = $true }
            foreach ($n in @($ref.labelNames)) { [void]$labelNames.Add($n) }
        }
        $created = ''
        foreach ($prop in @('WhenCreated', 'WhenCreatedUTC', 'CreationTimeUtc')) {
            if ($p.PSObject.Properties.Name -contains $prop -and $p.$prop) { $created = ([datetime]$p.$prop).ToString('yyyy-MM-dd'); break }
        }
        $items.Add([pscustomobject]@{
            name = [string]$p.Name; guid = Get-PpaOptionalGuid $p; mode = [string]$p.Mode; sits = @($sits)
            hasLabelCondition = $hasLabelCondition
            labelRefs = @($labelNames | Select-Object -Unique)
            copilotLocations = @($signals.copilotLocations)
            oneClick = [bool]$signals.oneClick
            parseFallback = [bool]$signals.parseFallback
            created = $created
        })
    }

    $dspmItems   = @($(if ($rawDspm.Status -eq 'Ok') { Get-PpaDspmPolicyItems $rawDspm.Data } else { @() }))
    $appRetItems = @($(if ($rawAppRet.Status -eq 'Ok') { Get-PpaAppRetentionItems $rawAppRet.Data } else { @() }))
    $ccItems     = @($(if ($rawCcPols.Status -eq 'Ok' -and $rawCcRules.Status -eq 'Ok') {
        Get-PpaCcCopilotItems $rawCcPols.Data $rawCcRules.Data
    } else { @() }))
    $outcome = Resolve-PpaCollectorOutcome `
        -ReadStatuses @($rawPols.Status, $rawRules.Status, $rawDspm.Status, $rawAppRet.Status, $rawRet.Status, $rawCcPols.Status, $rawCcRules.Status) `
        -ItemCount ($items.Count + $dspmItems.Count + $appRetItems.Count + @($rawRet.Data).Count + $ccItems.Count)

    return [pscustomobject]@{
        outcome         = $outcome
        copilotPolicies = [pscustomobject]@{
            status = $rawPols.Status; error = $rawPols.Error; items = $items.ToArray()
            thirdPartyAiDlpPolicies = @($thirdPartyAiDlp | Select-Object -Unique)
        }
        dspmPolicies = [pscustomobject]@{
            status = $rawDspm.Status; error = $rawDspm.Error
            items = $dspmItems
        }
        appRetention = [pscustomobject]@{
            status = $rawAppRet.Status; error = $rawAppRet.Error
            items = $appRetItems
        }
        # Classic retention family: only the legacy pre-split combined "Teams chats and
        # Copilot interactions" signal (TeamsChatLocation populated) plus a total count -
        # the full classic projection stays with the Retention section's own collector.
        retentionLegacy = [pscustomobject]@{
            status = $rawRet.Status; error = $rawRet.Error
            totalCount = @($rawRet.Data).Count
            teamsChatPolicies = @($(if ($rawRet.Status -eq 'Ok') {
                @($rawRet.Data) | Where-Object { @($_.TeamsChatLocation | Where-Object { $_ }).Count -gt 0 } | ForEach-Object { [string]$_.Name }
            } else { @() }))
        }
        ccCopilot = [pscustomobject]@{
            policiesStatus = $rawCcPols.Status; policiesError = $rawCcPols.Error
            rulesStatus = $rawCcRules.Status; rulesError = $rawCcRules.Error
            items = $ccItems
        }
    }
}
