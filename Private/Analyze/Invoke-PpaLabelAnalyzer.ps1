# Invoke-PpaLabelAnalyzer.ps1 - analyzer for section 01 (Sensitivity Labels).
# Turns the Get-PpaSensitivityLabels raw shape into the five findings LABELS-01..05 with
# statuses per CHECK_CATALOG.md. Pure function of its input (+ an -AsOf date for the
# simulation-age remark) so it is unit-testable with no tenant.
# ASCII-only source (Windows PowerShell 5.1). Depends on New-PpaFinding.ps1 / New-PpaSection.ps1.

Set-StrictMode -Off

function ConvertTo-PpaScopeDisplay {
    # The internal-name -> friendly-name mapping table for sensitivity-label scope
    # display (Wave 5 cleanup Part 3 formalized the policy). DISPLAY-TIME ONLY:
    # collectors and snapshots keep the raw canonical ContentType tokens - mapping
    # earlier would make old raw snapshots diff against new friendly ones, turning
    # a display tweak into phantom delta churn (guard pinned in Snapshot.Tests.ps1).
    # Entries are added ONLY for internal values confirmed to render in a real
    # report - no speculative rows; unconfirmed tokens pass through raw below.
    # 'Teamwork' -> 'Teams' confirmed on the live TEST report (Wave 5 Part 3).
    param([string[]]$Tokens)
    $map = @{
        'File' = 'Files'; 'Email' = 'Emails'; 'Site' = 'Sites'; 'UnifiedGroup' = 'Groups'
        'Teamwork' = 'Teams'
        'TeamworkChannel' = 'Teams channels'; 'SchematizedData' = 'Schematized data'; 'PurviewAssets' = 'Purview assets'
    }
    $out = foreach ($t in @($Tokens)) { if ($map.ContainsKey($t)) { $map[$t] } else { $t } }
    return (@($out) -join ', ')
}

function Invoke-PpaLabelAnalyzer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Raw,
        [datetime]$AsOf = (Get-Date),
        # Parsed Data/license-requirements.json (static annotation map, not detection).
        $LicenseMap
    )

    $labels = @($Raw.labels.items)
    $pols   = @($Raw.policies.items)
    $autos  = @($Raw.autoLabels.items)
    $findings = New-Object System.Collections.Generic.List[object]

    # --- LABELS-01: taxonomy ---
    $lm01 = @(
        @{ label = 'Microsoft Purview portal - Information Protection'; url = 'https://purview.microsoft.com'; tag = 'portal' }
        @{ label = 'Overview of sensitivity labels'; url = 'https://learn.microsoft.com/en-us/purview/sensitivity-labels'; tag = 'docs' }
    )
    if ($labels.Count -gt 0) {
        $byGuid = @{}
        foreach ($l in $labels) { if ($l.guid) { $byGuid[$l.guid] = $l.name } }
        $rows01 = foreach ($l in ($labels | Sort-Object priority)) {
            $isSub = -not [string]::IsNullOrEmpty($l.parentId)
            $disp  = if ($isSub -and $byGuid.ContainsKey($l.parentId)) { "$($byGuid[$l.parentId]) \ $($l.name)" } else { $l.name }
            New-PpaRow -Cells @($disp, [string]$l.priority, (ConvertTo-PpaScopeDisplay $l.scopes)) -Status 'Informational' -Indent:$isSub
        }
        $findings.Add((New-PpaFinding -Id 'LABELS-01' -DomId 'f-lab-1' -Title 'Taxonomy is defined' -Status 'Informational' `
            -Whyline 'A clear, ordered taxonomy is the foundation auto-labeling, DLP and retention build on. The tenant defines:' `
            -Table (New-PpaTable -Columns @('Label', 'Priority', 'Scope', 'Status') -Rows @($rows01)) -LearnMore $lm01))
    }
    else {
        $findings.Add((New-PpaFinding -Id 'LABELS-01' -DomId 'f-lab-1' -Title 'No sensitivity label taxonomy defined' -Status 'Improvement' `
            -Whyline 'Without a label taxonomy there is no foundation for auto-labeling, DLP or retention to build on.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @((New-PpaRow -Cells @('Sensitivity labels', '0') -Status 'Improvement'))) -LearnMore $lm01))
    }

    # --- LABELS-02: published to users ---
    $enabledPols = @($pols | Where-Object { $_.enabled })
    $lm02 = @(@{ label = 'Create and publish sensitivity labels'; url = 'https://learn.microsoft.com/en-us/purview/create-sensitivity-labels'; tag = 'docs' })
    if ($pols.Count -gt 0) {
        $status02 = if ($enabledPols.Count -gt 0) { 'OK' } else { 'Improvement' }
        $rows02 = foreach ($p in $pols) {
            New-PpaRow -Cells @($p.name, (@($p.labels) -join ', '), $p.scope) -Status ($(if ($p.enabled) { 'OK' } else { 'Improvement' }))
        }
        $findings.Add((New-PpaFinding -Id 'LABELS-02' -DomId 'f-lab-2' -Title 'Labels are published to users' -Status $status02 `
            -Whyline 'Labels only classify content once published to the people creating it.' `
            -Table (New-PpaTable -Columns @('Label Policy', 'Labels', 'Assigned To', 'Status') -Rows @($rows02)) -LearnMore $lm02))
    }
    else {
        $findings.Add((New-PpaFinding -Id 'LABELS-02' -DomId 'f-lab-2' -Title 'Labels are not published to users' -Status 'Improvement' `
            -Whyline 'Labels exist but no label policy publishes them, so users cannot apply them.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @((New-PpaRow -Cells @('Label policies', '0') -Status 'Improvement'))) -LearnMore $lm02))
    }

    # --- LABELS-03: auto-labeling ---
    $lm03 = @(
        @{ label = 'Microsoft Purview portal - Information Protection'; url = 'https://purview.microsoft.com'; tag = 'portal' }
        @{ label = 'Compliance Manager - improvement actions'; url = 'https://purview.microsoft.com'; tag = 'portal' }
        @{ label = 'Overview of sensitivity labels'; url = 'https://learn.microsoft.com/en-us/purview/sensitivity-labels'; tag = 'docs' }
        @{ label = 'How to apply a sensitivity label to content automatically'; url = 'https://learn.microsoft.com/en-us/purview/apply-sensitivity-label-automatically'; tag = 'docs' }
    )
    $enforcing = @($autos | Where-Object { $_.mode -match '(?i)enforce' })
    $simulating = @($autos | Where-Object { $_.mode -match '(?i)test|simul' })
    if ($autos.Count -eq 0) {
        $findings.Add((New-PpaFinding -Id 'LABELS-03' -DomId 'f-lab-3' -Title 'No auto-labeling configured' -Status 'Recommendation' -Requires (Get-PpaRequirement $LicenseMap 'LABELS-03') `
            -Whyline 'Automatic labeling reduces reliance on users to classify correctly; none is configured.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @((New-PpaRow -Cells @('Auto-labeling policies', '0') -Status 'Recommendation'))) -LearnMore $lm03))
    }
    else {
        $status03 = if ($simulating.Count -gt 0) { 'Improvement' } elseif ($enforcing.Count -gt 0) { 'OK' } else { 'Improvement' }
        $title03  = if ($simulating.Count -gt 0) { 'Auto-labeling is not enforcing' } else { 'Auto-labeling is enforcing' }
        $rows03 = foreach ($a in $autos) {
            $isSim    = $a.mode -match '(?i)test|simul'
            $modeDisp = if ($isSim) { 'Simulation' } elseif ($a.mode -match '(?i)enforce') { 'Enforce' } else { [string]$a.mode }
            $remarks  = New-Object System.Collections.Generic.List[string]
            if ($isSim -and $a.simulationStartDate) {
                $start = [datetime]$a.simulationStartDate
                $days  = [int]([math]::Round(($AsOf - $start).TotalDays))
                $remarks.Add("running in simulation since $($start.ToString('dd-MMM-yyyy')) ($days days). Simulation shows $('{0:N0}' -f $a.simulationItemCount) items would be labeled - consider turning the policy on.")
            }
            # Wave 5 cleanup Part 2: the Conditions cell distinguishes where the
            # conditions came from - flat property (unchanged passthrough), grouped
            # AdvancedRule (flat sorted name list + distinct count), present-but-
            # unparsed, genuinely none, or rule-read-degraded. Items from older
            # captures carry no conditionsSource marker and keep the legacy joined
            # rendering exactly.
            $rowStatus = $(if ($isSim) { 'Improvement' } else { 'OK' })
            $condCell  = (@($a.sits) -join ', ')
            $src = ''
            if ($a.PSObject.Properties.Name -contains 'conditionsSource') { $src = [string]$a.conditionsSource }
            switch ($src) {
                'grouped' {
                    $condCell = $condCell + ' - ' + ([string]@($a.sits).Count) + ' distinct (grouped conditions)'
                    $remarks.Add('Conditions parsed from the grouped-condition rule (AdvancedRule): named sensitive info types and trainable classifiers combined; AND/OR grouping not shown.')
                }
                'unparsed' {
                    $condCell  = 'Conditions present - not parsed'
                    $rowStatus = 'Verify manually'
                    $remarks.Add('The policy rule stores grouped conditions (AdvancedRule) in a shape this run could not parse - review the policy conditions in the Purview portal.')
                }
                'none' {
                    $condCell = 'None detected'
                }
                'unreadable' {
                    $condCell  = 'Conditions not readable this run'
                    $rowStatus = 'Verify manually'
                    $remarks.Add('The auto-labeling rule read did not complete, so conditions could not be read - review the policy conditions in the Purview portal.')
                }
            }
            $remark = $(if ($remarks.Count -gt 0) { $remarks -join ' ' } else { $null })
            New-PpaRow -Cells @($a.name, $condCell, $modeDisp) -Status $rowStatus -Remark $remark
        }
        $findings.Add((New-PpaFinding -Id 'LABELS-03' -DomId 'f-lab-3' -Title $title03 -Status $status03 -Requires (Get-PpaRequirement $LicenseMap 'LABELS-03') `
            -Whyline 'Automatic labeling reduces reliance on users to classify correctly; in simulation it observes but never applies.' `
            -Table (New-PpaTable -Columns @('Auto-labeling Policy', 'Conditions (SITs)', 'Mode', 'Status') -Rows @($rows03)) -LearnMore $lm03))
    }

    # --- LABELS-04: container labels ---
    $lm04 = @(@{ label = 'Use sensitivity labels to protect containers (groups & sites)'; url = 'https://learn.microsoft.com/en-us/purview/sensitivity-labels-teams-groups-sites'; tag = 'docs' })
    $containerLabels = @($labels | Where-Object { $_.scopes -contains 'Site' -or $_.scopes -contains 'UnifiedGroup' })
    $c = $Raw.containers
    $groupCov = if ($c -and $c.groups) { "$($c.groups.labeled) of $($c.groups.total) labeled" } else { $null }
    $siteCov  = if ($c -and $c.sites)  { "$($c.sites.labeled) of $($c.sites.total) labeled" }  else { $null }
    if ($containerLabels.Count -eq 0) {
        $rows04 = @(
            New-PpaRow -Cells @('Microsoft 365 Groups / Teams', ($(if ($groupCov) { $groupCov } else { 'Inventory not collected' }))) -Status ($(if ($groupCov) { 'Recommendation' } else { 'Verify manually' }))
            New-PpaRow -Cells @('SharePoint sites', ($(if ($siteCov) { $siteCov } else { 'Inventory not collected' }))) -Status ($(if ($siteCov) { 'Recommendation' } else { 'Verify manually' }))
        )
        $findings.Add((New-PpaFinding -Id 'LABELS-04' -DomId 'f-lab-4' -Title 'No container labels for Teams / Sites / Groups' -Status 'Recommendation' `
            -Whyline 'Container labels govern guest access, external sharing and unmanaged-device rules on collaborative workspaces.' `
            -Table (New-PpaTable -Columns @('Container type', 'Coverage', 'Status') -Rows @($rows04)) -LearnMore $lm04))
    }
    else {
        $findings.Add((New-PpaFinding -Id 'LABELS-04' -DomId 'f-lab-4' -Title 'Container labels are in use' -Status 'OK' `
            -Whyline 'Container labels govern guest access, external sharing and unmanaged-device rules on collaborative workspaces.' `
            -Table (New-PpaTable -Columns @('Container type', 'Coverage', 'Status') -Rows @((New-PpaRow -Cells @('Container-scoped labels', "$($containerLabels.Count) defined") -Status 'OK'))) -LearnMore $lm04))
    }

    # --- LABELS-05: Azure Rights Management for Exchange Online (Wave 6 Part 2) ---
    # $null means "not read this session" (EXO session absent, read failed, or the
    # property missing) - the absence of the read is never reported as Disabled.
    # Older raw captures carry no irmConfig block at all: same Verify manually path.
    $lm05 = @(@{ label = 'Encryption in Microsoft 365'; url = 'https://learn.microsoft.com/en-us/purview/encryption'; tag = 'docs' })
    $why05 = 'Azure RMS is the encryption engine behind sensitivity labels and encrypted mail; with it disabled, protection actions across Exchange silently do nothing.'
    $rmsKnown = ($null -ne $Raw.irmConfig) -and ($null -ne $Raw.irmConfig.azureRmsEnabled)
    $rmsOn    = $rmsKnown -and [bool]$Raw.irmConfig.azureRmsEnabled
    if (-not $rmsKnown) {
        $findings.Add((New-PpaFinding -Id 'LABELS-05' -DomId 'f-lab-5' -Title 'Azure Rights Management not readable this session' -Status 'Verify manually' `
            -Whyline $why05 `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Azure Rights Management (Exchange Online)', 'Not readable this session (Exchange Online session not established?)') -Status 'Verify manually'
            )) -LearnMore $lm05))
    }
    elseif ($rmsOn) {
        $findings.Add((New-PpaFinding -Id 'LABELS-05' -DomId 'f-lab-5' -Title 'Azure Rights Management is enabled for Exchange Online' -Status 'OK' `
            -Whyline $why05 `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Azure Rights Management (Exchange Online)', 'Enabled') -Status 'OK'
            )) -LearnMore $lm05))
    }
    else {
        $findings.Add((New-PpaFinding -Id 'LABELS-05' -DomId 'f-lab-5' -Title 'Azure Rights Management is disabled for Exchange Online' -Status 'Improvement' `
            -Whyline $why05 `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Azure Rights Management (Exchange Online)', 'Disabled (AzureRMSLicensingEnabled = false)') -Status 'Improvement'
                New-PpaRow -Cells @('Context', 'Default-on for tenants created after 2018 - a disabled state is usually a deliberate opt-out; confirm intent') -Status 'Informational'
            )) -LearnMore $lm05))
    }

    # --- section glance ---
    $autoState = if ($simulating.Count -gt 0) { 'auto-label in sim' } elseif ($enforcing.Count -gt 0) { 'auto-label on' } else { 'no auto-label' }
    $mid = Get-PpaMidDot
    $glance = New-PpaGlance -Name 'Sensitivity Labels' -Metric "$($labels.Count) labels" -Sub "$($pols.Count) policies $mid $autoState"

    return New-PpaSection -Id 'Sensitivity_Labels' -Title 'Sensitivity Labels' -Group 'Microsoft Information Protection' `
        -GroupIcon 'fas fa-shield-alt' -Glance $glance -Findings $findings.ToArray()
}
