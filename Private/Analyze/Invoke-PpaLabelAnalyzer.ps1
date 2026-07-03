# Invoke-PpaLabelAnalyzer.ps1 - analyzer for section 01 (Sensitivity Labels).
# Turns the Get-PpaSensitivityLabels raw shape into the four findings LABELS-01..04 with
# statuses per CHECK_CATALOG.md. Pure function of its input (+ an -AsOf date for the
# simulation-age remark) so it is unit-testable with no tenant.
# ASCII-only source (Windows PowerShell 5.1). Depends on New-PpaFinding.ps1 / New-PpaSection.ps1.

Set-StrictMode -Off

function ConvertTo-PpaScopeDisplay {
    param([string[]]$Tokens)
    $map = @{
        'File' = 'Files'; 'Email' = 'Emails'; 'Site' = 'Sites'; 'UnifiedGroup' = 'Groups'
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
            $remark   = $null
            if ($isSim -and $a.simulationStartDate) {
                $start = [datetime]$a.simulationStartDate
                $days  = [int]([math]::Round(($AsOf - $start).TotalDays))
                $remark = "running in simulation since $($start.ToString('dd-MMM-yyyy')) ($days days). Simulation shows $('{0:N0}' -f $a.simulationItemCount) items would be labeled - consider turning the policy on."
            }
            New-PpaRow -Cells @($a.name, (@($a.sits) -join ', '), $modeDisp) -Status ($(if ($isSim) { 'Improvement' } else { 'OK' })) -Remark $remark
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

    # --- section glance ---
    $autoState = if ($simulating.Count -gt 0) { 'auto-label in sim' } elseif ($enforcing.Count -gt 0) { 'auto-label on' } else { 'no auto-label' }
    $mid = Get-PpaMidDot
    $glance = New-PpaGlance -Name 'Sensitivity Labels' -Metric "$($labels.Count) labels" -Sub "$($pols.Count) policies $mid $autoState"

    return New-PpaSection -Id 'Sensitivity_Labels' -Title 'Sensitivity Labels' -Group 'Microsoft Information Protection' `
        -GroupIcon 'fas fa-shield-alt' -Glance $glance -Findings $findings.ToArray()
}
