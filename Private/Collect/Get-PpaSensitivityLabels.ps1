# Get-PpaSensitivityLabels.ps1 - collector for section 01 (Sensitivity Labels).
# Reads Get-Label, Get-LabelPolicy, Get-AutoSensitivityLabelPolicy and
# Get-AutoSensitivityLabelRule (all read-only) and projects each to a client-safe
# metadata shape: names, priorities, scopes, modes, SIT NAMES only - never document
# content or matched values (PLAN.md guardrails).
# ASCII-only source (Windows PowerShell 5.1). Depends on Invoke-PpaReadCmdlet.ps1.
#
# Container coverage (LABELS-04 "0 of 143 labeled") has no single read-only cmdlet; the
# collector marks it NotCollected and the analyzer degrades. A future phase can populate
# it from Graph groups + SPO site inventory.
#
# Wave 5 cleanup Part 2 (grouped conditions): policies built with grouped conditions
# leave the flat SensitiveInformationTypeNames property empty and store the conditions
# as an AdvancedRule JSON string on the RULE. When the flat property is empty, this
# collector flattens the rule blob into the same sits field (distinct NAMES - named
# SITs and trainable classifiers alike - ordinal-ignore-case sorted for engine-stable
# snapshots) and stamps conditionsSource: flat | grouped | unparsed | none | unreadable.
# The raw AdvancedRule blob is parsed transiently and NEVER persisted: snapshot items
# serialize collector output verbatim and the blob can carry non-name condition values.

Set-StrictMode -Off

function Get-PpaAdvancedRuleConditionNames {
    # Flatten Get-AutoSensitivityLabelRule AdvancedRule JSON string(s) into the
    # distinct detected-item names they reference. JSON paths pinned from the REAL
    # committed capture (Samples/sample-raw/autolabel-advancedrule.json):
    #   Condition.SubConditions[] (recursing into nested SubConditions) ->
    #   ConditionName 'ContentContainsSensitiveInformation' -> Value[] -> Groups[]
    #   -> Sensitivetypes[] -> Name  (Classifiertype 'MLModel' marks trainable
    #   classifiers - captured the same as named SITs, never filtered out).
    # The AND/OR group operators are deliberately discarded (ruled: present the set
    # of things detected, not the boolean logic); empty operator-only group entries
    # (observed in the real blob) are tolerated. Unparseable blobs contribute
    # nothing - the CALLER distinguishes unparsed from none by blob presence.
    param([string[]]$Texts)
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($text in @($Texts)) {
        $parsed = ConvertFrom-PpaJsonText $text
        if ($null -eq $parsed -or $null -eq $parsed.Condition) { continue }
        $stack = New-Object System.Collections.Generic.Stack[object]
        $stack.Push($parsed.Condition)
        while ($stack.Count -gt 0) {
            $node = $stack.Pop()
            if ($null -eq $node) { continue }
            foreach ($sub in @($node.SubConditions)) {
                if ($null -eq $sub) { continue }
                if ($null -ne $sub.SubConditions) { $stack.Push($sub); continue }
                if ([string]$sub.ConditionName -ne 'ContentContainsSensitiveInformation') { continue }
                foreach ($val in @($sub.Value)) {
                    if ($null -eq $val) { continue }
                    foreach ($grp in @($val.Groups)) {
                        if ($null -eq $grp) { continue }
                        foreach ($st in @($grp.Sensitivetypes)) {
                            if ($null -eq $st) { continue }
                            $n = [string]$st.Name
                            if (-not [string]::IsNullOrEmpty($n)) { $found.Add($n) }
                        }
                    }
                }
            }
        }
    }
    # Dedupe (keep first casing) + sort, both ordinal-ignore-case: deterministic
    # across PS 5.1 and 7 regardless of culture (pinned by the contract tests).
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $distinct = New-Object System.Collections.Generic.List[string]
    foreach ($n in $found) { if ($seen.Add($n)) { $distinct.Add($n) } }
    $sorted = $distinct.ToArray()
    [Array]::Sort($sorted, [System.StringComparer]::OrdinalIgnoreCase)
    return @($sorted)
}

function ConvertTo-PpaScopeTokens {
    # Normalize a Get-Label ContentType value (comma string, array, or flags) to tokens.
    param($ContentType)
    if ($null -eq $ContentType) { return @() }
    if ($ContentType -is [array]) { return @($ContentType | ForEach-Object { [string]$_ }) }
    return @(([string]$ContentType) -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-PpaSensitivityLabels {
    [CmdletBinding()]
    param()

    $rawLabels    = Invoke-PpaReadCmdlet -Name 'Get-Label'
    $rawPols      = Invoke-PpaReadCmdlet -Name 'Get-LabelPolicy'
    $rawAuto      = Invoke-PpaReadCmdlet -Name 'Get-AutoSensitivityLabelPolicy'
    $rawAutoRules = Invoke-PpaReadCmdlet -Name 'Get-AutoSensitivityLabelRule'
    # LABELS-05 (Wave 6 reincorporation Part 2): Azure RMS state. Exchange Online
    # cmdlet - the ONE read in this collector that needs the EXO session rather
    # than Security & Compliance; a missing session degrades only the LABELS-05
    # finding (containers precedent), never the section outcome.
    $rawIrm       = Invoke-PpaReadCmdlet -Name 'Get-IRMConfiguration'

    $labelItems = foreach ($l in @($rawLabels.Data)) {
        $displayName = if ($l.DisplayName) { [string]$l.DisplayName } else { [string]$l.Name }
        [pscustomobject]@{
            name     = $displayName
            guid     = [string]$l.Guid
            priority = [int]($l.Priority)
            scopes   = @(ConvertTo-PpaScopeTokens $l.ContentType)
            parentId = [string]$l.ParentId
        }
    }

    $policyItems = foreach ($p in @($rawPols.Data)) {
        # "Assigned To" from the location properties CHECK_CATALOG documents for LABELS-02
        # (ExchangeLocation / ModernGroupLocation). 'All' means published to all users.
        # Real Get-LabelPolicy has no ScopeSummary; an empty scope renders as a dash.
        $locs = @()
        $locs += @($p.ExchangeLocation | ForEach-Object { [string]$_ })
        $locs += @($p.ModernGroupLocation | ForEach-Object { [string]$_ })
        $locs = @($locs | Where-Object { $_ } | Select-Object -Unique)
        $scope = if ($locs -contains 'All') { 'All users' } elseif ($locs.Count -gt 0) { ($locs -join ', ') } else { '' }
        [pscustomobject]@{
            name    = [string]$p.Name
            guid    = Get-PpaOptionalGuid $p
            labels  = @($p.Labels | ForEach-Object { [string]$_ })
            enabled = [bool]($p.Enabled -ne $false)
            scope   = $scope
        }
    }

    $autoItems = foreach ($a in @($rawAuto.Data)) {
        # Wave 5 cleanup Part 2: sits is the canonical detected-item name set. Flat
        # property populated -> unchanged passthrough (cmdlet order kept). Flat empty
        # -> flatten the associated rules' AdvancedRule blobs into sits (sorted) and
        # record where the answer came from so downstream renders the four outcomes
        # distinctly and the snapshot carries the derived set, not an empty array.
        $sits = @($a.SensitiveInformationTypeNames | ForEach-Object { [string]$_ } | Where-Object { $_ })
        $condSource = 'flat'
        if ($sits.Count -eq 0) {
            if ($rawAutoRules.Status -ne 'Ok') { $condSource = 'unreadable' }
            else {
                # Associate rules by their policy reference, else name equality
                # (mirrors the retention and CC Copilot rule associations).
                $blobs = New-Object System.Collections.Generic.List[string]
                foreach ($r in @($rawAutoRules.Data)) {
                    if ($null -eq $r) { continue }
                    $assoc = $false
                    foreach ($prop in @('Policy', 'ParentPolicyName')) {
                        if ($r.PSObject.Properties.Name -contains $prop -and $r.$prop) {
                            $ref = [string]$r.$prop
                            if ($ref -eq [string]$a.Name -or ($a.PSObject.Properties.Name -contains 'Guid' -and $ref -eq [string]$a.Guid)) { $assoc = $true; break }
                        }
                    }
                    if (-not $assoc -and ([string]$r.Name) -eq ([string]$a.Name)) { $assoc = $true }
                    if (-not $assoc) { continue }
                    if ($r.PSObject.Properties.Name -contains 'AdvancedRule' -and -not [string]::IsNullOrWhiteSpace([string]$r.AdvancedRule)) {
                        $blobs.Add([string]$r.AdvancedRule)
                    }
                }
                if ($blobs.Count -eq 0) { $condSource = 'none' }
                else {
                    $names = @(Get-PpaAdvancedRuleConditionNames -Texts $blobs.ToArray())
                    if ($names.Count -gt 0) { $sits = $names; $condSource = 'grouped' }
                    else { $condSource = 'unparsed' }
                }
            }
        }
        [pscustomobject]@{
            name                = [string]$a.Name
            guid                = Get-PpaOptionalGuid $a
            mode                = [string]$a.Mode
            # Part D matrix grounding (documented-only shape): auto-labeling
            # supports Exchange/SharePoint/OneDrive locations only.
            locationScope       = [pscustomobject]@{
                exchange   = (Get-PpaLocationScopeToken $a.ExchangeLocation)
                sharePoint = (Get-PpaLocationScopeToken $a.SharePointLocation)
                oneDrive   = (Get-PpaLocationScopeToken $a.OneDriveLocation)
            }
            locationExceptions  = [pscustomobject]@{
                exchange   = (Test-PpaLocationException $a.ExchangeLocationException)
                sharePoint = (Test-PpaLocationException $a.SharePointLocationException)
                oneDrive   = (Test-PpaLocationException $a.OneDriveLocationException)
            }
            sits                = @($sits)
            conditionsSource    = $condSource
            simulationStartDate = ConvertTo-PpaIso8601 $a.SimulationStartDate
            simulationItemCount = [int]($a.SimulationItemCount)
        }
    }

    # LABELS-05: $null means "not read this session" (failed EXO read OR the property
    # absent from the returned object) - distinct from $false, so the analyzer degrades
    # to Verify manually instead of guessing a boolean.
    $rmsEnabled = $null
    if ($rawIrm.Status -eq 'Ok' -and @($rawIrm.Data).Count -gt 0) {
        $irm = $rawIrm.Data[0]
        if ($irm.PSObject.Properties.Name -contains 'AzureRMSLicensingEnabled' -and $null -ne $irm.AzureRMSLicensingEnabled) {
            $rmsEnabled = [bool]$irm.AzureRMSLicensingEnabled
        }
    }

    # Outcome from the three original reads only - the containers block is NotCollected
    # by design and must not degrade the outcome, and the Wave 5 Part 2 rule read is
    # excluded the same way (containers precedent): a tenant/session without
    # Get-AutoSensitivityLabelRule degrades ONLY the conditions display
    # (conditionsSource 'unreadable'), never the section or the coverage matrix.
    # The Get-IRMConfiguration read (EXO session) is excluded for the same reason:
    # it degrades only LABELS-05.
    return [pscustomobject]@{
        outcome    = Resolve-PpaCollectorOutcome -ReadStatuses @($rawLabels.Status, $rawPols.Status, $rawAuto.Status) -ItemCount (@($labelItems).Count + @($policyItems).Count + @($autoItems).Count)
        labels     = [pscustomobject]@{ status = $rawLabels.Status; error = $rawLabels.Error; items = @($labelItems) }
        policies   = [pscustomobject]@{ status = $rawPols.Status;   error = $rawPols.Error;   items = @($policyItems) }
        autoLabels = [pscustomobject]@{
            status = $rawAuto.Status; error = $rawAuto.Error
            rulesStatus = $rawAutoRules.Status; rulesError = $rawAutoRules.Error
            items = @($autoItems)
        }
        containers = [pscustomobject]@{ status = 'NotCollected';    groups = $null;           sites = $null }
        irmConfig  = [pscustomobject]@{ status = $rawIrm.Status; error = $rawIrm.Error; azureRmsEnabled = $rmsEnabled }
    }
}
