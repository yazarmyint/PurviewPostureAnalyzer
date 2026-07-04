# Get-PpaCoverageModel.ps1 - the coverage matrix analyzer (Wave 4 spec section 5).
# A PURE PROJECTION: builds the CoverageModel from ALREADY-NORMALIZED collector
# outputs. It performs NO tenant reads, creates NO findings, assigns NO severities;
# cells anchor-link to EXISTING check ids only. Pinned by Tests/Coverage.Tests.ps1;
# the read-only guard scans this file like every other Private file.
#
# Grid: 7 workloads x 3 location-scoped controls. Cell states (closed enum):
#   Covered | Partial | Test-only | None | Unknown | N/A     (+ 'Held' OUTSIDE the
# enum for the Copilot x Retention render-hold - excluded from every total).
# Partial always carries >=1 reason code: ScopedInclude, HasExceptions,
# SubsetOfLocations, AdaptiveScope, RuleDisabled.
# Aggregation across policies: best-of Covered > Partial > Test-only > None.
# Unknown iff the governing collector outcome is outside { Populated, Empty } -
# never otherwise - and Unknown never counts toward any gap total.
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function Get-PpaCoverageApplicability {
    $path = Join-Path $PSScriptRoot 'ppa-coverage-applicability.json'
    return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Get-PpaCoverageProvenance {
    $path = Join-Path $PSScriptRoot 'ppa-coverage-provenance.json'
    return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Get-PpaCoverageItemScope {
    # Scope token for one normalized policy item and workload key. Prefers the
    # Part D locationScope projection; falls back to the legacy shapes so old
    # fixtures/snapshots (sparse regression case) still classify:
    #   - DLP boolean object: true -> 'All', false -> 'None'
    #   - Retention token array: token present -> 'All', absent -> 'None'
    param($Item, [string]$Key)
    if ($Item.PSObject.Properties.Name -contains 'locationScope' -and $null -ne $Item.locationScope) {
        if ($Item.locationScope.PSObject.Properties.Name -contains $Key) { return [string]$Item.locationScope.$Key }
        return 'None'
    }
    if ($Item.PSObject.Properties.Name -contains 'locations' -and $null -ne $Item.locations) {
        $loc = $Item.locations
        if ($loc -is [System.Management.Automation.PSCustomObject]) {
            if ($loc.PSObject.Properties.Name -contains $Key -and $loc.$Key) { return 'All' }
            return 'None'
        }
        $tokenMap = @{ exchange = 'Exchange'; sharePoint = 'SharePoint'; oneDrive = 'OneDrive'; groups = 'Groups' }
        if ($tokenMap.ContainsKey($Key) -and (@($loc) -contains $tokenMap[$Key])) { return 'All' }
        return 'None'
    }
    return 'None'
}

function Get-PpaCoverageItemException {
    param($Item, [string]$Key)
    if ($Item.PSObject.Properties.Name -contains 'locationExceptions' -and $null -ne $Item.locationExceptions) {
        if ($Item.locationExceptions.PSObject.Properties.Name -contains $Key) { return [bool]$Item.locationExceptions.$Key }
    }
    return $false
}

function Merge-PpaCoverageContribution {
    # Best-of aggregation (ruled): Covered > Partial > Test-only > None. Reason
    # codes surface only when the FINAL state is Partial, as the union of reasons
    # from the Partial contributions.
    param($Contributions)
    $rank = @{ 'Covered' = 3; 'Partial' = 2; 'Test-only' = 1; 'None' = 0 }
    $state = 'None'
    $contributors = New-Object System.Collections.Generic.List[string]
    foreach ($c in @($Contributions)) {
        if ($null -eq $c) { continue }
        $contributors.Add([string]$c.name)
        if ($rank[[string]$c.tier] -gt $rank[$state]) { $state = [string]$c.tier }
    }
    $reasons = @()
    if ($state -eq 'Partial') {
        $all = New-Object System.Collections.Generic.List[string]
        foreach ($c in @($Contributions)) {
            if ($null -ne $c -and [string]$c.tier -eq 'Partial') {
                foreach ($r in @($c.reasons)) { if ($all -notcontains $r) { $all.Add($r) } }
            }
        }
        $reasons = @($all | Sort-Object)
    }
    return [pscustomobject]@{ state = $state; reasons = $reasons; contributors = $contributors.ToArray() }
}

function Get-PpaCoverageModel {
    [CmdletBinding()]
    param(
        # Hashtable: section id -> normalized collector output (null/absent allowed).
        [Parameter(Mandatory = $true)] $RawMap
    )

    $applic = Get-PpaCoverageApplicability
    $proven = Get-PpaCoverageProvenance
    $readable = @('Populated', 'Empty')

    $rowDefs = @(
        @{ key = 'exchange';   label = 'Exchange Online' }
        @{ key = 'sharePoint'; label = 'SharePoint' }
        @{ key = 'oneDrive';   label = 'OneDrive' }
        @{ key = 'teams';      label = 'Teams' }
        @{ key = 'endpoint';   label = 'Endpoint' }
        @{ key = 'powerBI';    label = 'Power BI' }
        @{ key = 'copilot';    label = 'Copilot' }
    )
    $colDefs = @(
        @{ key = 'dlp';       label = 'DLP';           section = 'Data_Loss_Prevention'; checkId = 'DLP-01' }
        @{ key = 'autoLabel'; label = 'Auto-labeling'; section = 'Sensitivity_Labels';   checkId = 'LABELS-03' }
        @{ key = 'retention'; label = 'Retention';     section = 'Retention';            checkId = 'RET-01' }
    )

    function Get-RawFor([string]$SectionId) {
        if ($RawMap -is [System.Collections.IDictionary]) {
            if ($RawMap.Contains($SectionId)) { return $RawMap[$SectionId] }
            return $null
        }
        return $RawMap.$SectionId
    }
    function Get-OutcomeFor([string]$SectionId) {
        $raw = Get-RawFor $SectionId
        if ($null -eq $raw) { return 'NotRun' }
        $o = [string]$raw.outcome
        if ([string]::IsNullOrEmpty($o)) { return 'NotRun' }
        return $o
    }

    # ---- contributions per column ----
    $dlpRaw = Get-RawFor 'Data_Loss_Prevention'
    $dlpRules = @()
    if ($null -ne $dlpRaw) { $dlpRules = @($dlpRaw.rules.items) }

    function Get-DlpContribution([string]$RowKey) {
        $out = New-Object System.Collections.Generic.List[object]
        if ($null -eq $dlpRaw) { return @() }
        foreach ($p in @($dlpRaw.policies.items)) {
            $scope = Get-PpaCoverageItemScope $p $RowKey
            if ($scope -eq 'None') { continue }
            $enforcing = Test-PpaDlpEnforcing ([string]$p.mode)
            if (-not $enforcing) {
                $out.Add([pscustomobject]@{ name = [string]$p.name; tier = 'Test-only'; reasons = @() })
                continue
            }
            $reasons = New-Object System.Collections.Generic.List[string]
            if ($scope -eq 'Scoped') { $reasons.Add('ScopedInclude') }
            if (Get-PpaCoverageItemException $p $RowKey) { $reasons.Add('HasExceptions') }
            $pr = @($dlpRules | Where-Object { [string]$_.policyName -eq [string]$p.name })
            if ($pr.Count -gt 0 -and @($pr | Where-Object { $_.disabled }).Count -eq $pr.Count) { $reasons.Add('RuleDisabled') }
            if ($reasons.Count -gt 0) { $out.Add([pscustomobject]@{ name = [string]$p.name; tier = 'Partial'; reasons = $reasons.ToArray() }) }
            else { $out.Add([pscustomobject]@{ name = [string]$p.name; tier = 'Covered'; reasons = @() }) }
        }
        return $out.ToArray()
    }

    function Get-CopilotDlpContribution {
        $raw = Get-RawFor 'DSPM_for_AI'
        if ($null -eq $raw) { return @() }
        $out = New-Object System.Collections.Generic.List[object]
        foreach ($p in @($raw.copilotPolicies.items)) {
            $tier = 'Test-only'
            if (Test-PpaDlpEnforcing ([string]$p.mode)) { $tier = 'Covered' }
            $out.Add([pscustomobject]@{ name = [string]$p.name; tier = $tier; reasons = @() })
        }
        return $out.ToArray()
    }

    function Get-AutoLabelContribution([string]$RowKey) {
        $raw = Get-RawFor 'Sensitivity_Labels'
        if ($null -eq $raw) { return @() }
        $out = New-Object System.Collections.Generic.List[object]
        foreach ($a in @($raw.autoLabels.items)) {
            $scope = Get-PpaCoverageItemScope $a $RowKey
            if ($scope -eq 'None') { continue }
            $enforcing = -not ([string]$a.mode -match '(?i)test|simul')
            if (-not $enforcing) {
                $out.Add([pscustomobject]@{ name = [string]$a.name; tier = 'Test-only'; reasons = @() })
                continue
            }
            $reasons = New-Object System.Collections.Generic.List[string]
            if ($scope -eq 'Scoped') { $reasons.Add('ScopedInclude') }
            if (Get-PpaCoverageItemException $a $RowKey) { $reasons.Add('HasExceptions') }
            if ($reasons.Count -gt 0) { $out.Add([pscustomobject]@{ name = [string]$a.name; tier = 'Partial'; reasons = $reasons.ToArray() }) }
            else { $out.Add([pscustomobject]@{ name = [string]$a.name; tier = 'Covered'; reasons = @() }) }
        }
        return $out.ToArray()
    }

    function Get-RetentionContribution([string]$RowKey) {
        $raw = Get-RawFor 'Retention'
        if ($null -eq $raw) { return @() }
        $out = New-Object System.Collections.Generic.List[object]
        foreach ($p in @($raw.policies.items)) {
            $scope = Get-PpaCoverageItemScope $p $RowKey
            # A Teams row is covered by either Teams retention location.
            if ($RowKey -eq 'teams') {
                $ch = Get-PpaCoverageItemScope $p 'teamsChannel'
                $chat = Get-PpaCoverageItemScope $p 'teamsChat'
                $scope = 'None'
                if ($ch -eq 'All' -or $chat -eq 'All') { $scope = 'All' }
                elseif ($ch -eq 'Scoped' -or $chat -eq 'Scoped') { $scope = 'Scoped' }
            }
            if ($scope -eq 'None') { continue }
            $reasons = New-Object System.Collections.Generic.List[string]
            if ($scope -eq 'Scoped') { $reasons.Add('SubsetOfLocations') }
            if ([bool]$p.adaptive) { $reasons.Add('AdaptiveScope') }
            if ($reasons.Count -gt 0) { $out.Add([pscustomobject]@{ name = [string]$p.name; tier = 'Partial'; reasons = $reasons.ToArray() }) }
            else { $out.Add([pscustomobject]@{ name = [string]$p.name; tier = 'Covered'; reasons = @() }) }
        }
        return $out.ToArray()
    }

    # ---- assemble the grid ----
    $cells = New-Object System.Collections.Generic.List[object]
    $degraded = New-Object System.Collections.Generic.List[object]
    $seenDegraded = @{}
    $counts = @{ 'Covered' = 0; 'Partial' = 0; 'Test-only' = 0; 'None' = 0; 'Unknown' = 0; 'N/A' = 0 }

    foreach ($row in $rowDefs) {
        foreach ($col in $colDefs) {
            $rowKey = [string]$row.key; $colKey = [string]$col.key

            $cell = [ordered]@{
                row = $rowKey; rowLabel = [string]$row.label
                column = $colKey; columnLabel = [string]$col.label
                state = ''; reasons = @(); contributors = @()
                provenance = [string]$proven.columns.$colKey.provenance
                checkId = [string]$col.checkId
                naReason = ''
            }

            # Copilot x Retention: RENDER-HOLD (ruled 5.6). Outside the enum,
            # excluded from every total; capture is NOT held (Part B writes the
            # objects regardless).
            if ($rowKey -eq 'copilot' -and $colKey -eq 'retention') {
                $cell.state = 'Held'
                $cell.checkId = 'AI-05'   # existing Wave 2 check, from CHECK_CATALOG.md
                $cells.Add([pscustomobject]$cell)
                continue
            }

            # Static applicability (reviewed data file) drives N/A cells.
            $na = @($applic.na | Where-Object { [string]$_.row -eq $rowKey -and [string]$_.column -eq $colKey })
            if ($na.Count -gt 0) {
                $cell.state = 'N/A'
                $cell.naReason = [string]$na[0].rationale
                $counts['N/A']++
                $cells.Add([pscustomobject]$cell)
                continue
            }

            # Governing collector: Copilot x DLP is grounded in the DSPM collector.
            $governId = [string]$col.section
            if ($rowKey -eq 'copilot' -and $colKey -eq 'dlp') { $governId = 'DSPM_for_AI' }
            $outcome = Get-OutcomeFor $governId
            if ($readable -notcontains $outcome) {
                $cell.state = 'Unknown'
                $counts['Unknown']++
                if (-not $seenDegraded.ContainsKey($governId)) {
                    $seenDegraded[$governId] = $true
                    $degraded.Add([pscustomobject]@{ collector = $governId; outcome = $outcome })
                }
                $cells.Add([pscustomobject]$cell)
                continue
            }

            $contrib = @()
            if ($colKey -eq 'dlp') {
                if ($rowKey -eq 'copilot') { $contrib = Get-CopilotDlpContribution }
                else { $contrib = Get-DlpContribution $rowKey }
            }
            elseif ($colKey -eq 'autoLabel') { $contrib = Get-AutoLabelContribution $rowKey }
            else { $contrib = Get-RetentionContribution $rowKey }

            $merged = Merge-PpaCoverageContribution $contrib
            $cell.state = $merged.state
            $cell.reasons = @($merged.reasons)
            $cell.contributors = @($merged.contributors)
            $counts[$merged.state]++
            $cells.Add([pscustomobject]$cell)
        }
    }

    # ---- tenant-level audit strip: grounded on the AuditConfig singleton, NOT
    # the audit collector outcome (Part A review addendum) ----
    $audRaw = Get-RawFor 'Audit'
    $audState = 'NotObserved'
    if ($null -ne $audRaw -and $audRaw.PSObject.Properties.Name -contains 'unifiedAuditEnabled' -and $null -ne $audRaw.unifiedAuditEnabled) {
        $audState = $(if ([bool]$audRaw.unifiedAuditEnabled) { 'On' } else { 'Off' })
    }

    # ---- principal-scoped strip: present/absent summaries with counts ----
    $labelsRaw = Get-RawFor 'Sensitivity_Labels'
    $pubCount = $null; $pubNote = ''
    if ($null -ne $labelsRaw -and $readable -contains (Get-OutcomeFor 'Sensitivity_Labels')) {
        $pubCount = @($labelsRaw.policies.items).Count
    } else { $pubNote = 'not readable this run' }
    $irmRaw = Get-RawFor 'Insider_Risk'
    $irmCount = $null; $irmNote = ''
    if ($null -ne $irmRaw -and $readable -contains (Get-OutcomeFor 'Insider_Risk')) {
        $irmCount = @($irmRaw.policies.items).Count
    } else { $irmNote = 'not readable this run' }
    $ccRaw = Get-RawFor 'Communication_Compliance'
    $ccCount = $null; $ccNote = ''
    if ($null -ne $ccRaw -and $readable -contains (Get-OutcomeFor 'Communication_Compliance')) {
        $ccCount = [int]$ccRaw.policies.count
    } else { $ccNote = 'not readable this run' }

    return [pscustomobject][ordered]@{
        rows    = @($rowDefs | ForEach-Object { [pscustomobject]@{ key = [string]$_.key; label = [string]$_.label } })
        columns = @($colDefs | ForEach-Object { [pscustomobject]@{ key = [string]$_.key; label = [string]$_.label } })
        cells   = $cells.ToArray()
        totals  = [pscustomobject][ordered]@{
            covered = $counts['Covered']; partial = $counts['Partial']; testOnly = $counts['Test-only']
            gaps = $counts['None']   # None only: Unknown, N/A and Held are NEVER gap-counted
            unknown = $counts['Unknown']; na = $counts['N/A']
        }
        banner  = [pscustomobject]@{ show = ($degraded.Count -gt 0); degraded = $degraded.ToArray() }
        auditStrip = [pscustomobject]@{ state = $audState; checkId = 'AUD-01'; sectionId = 'Audit' }
        principal = @(
            [pscustomobject]@{ name = 'Label publishing';         count = $pubCount; note = $pubNote; sectionId = 'Sensitivity_Labels';       checkId = 'LABELS-02' }
            [pscustomobject]@{ name = 'Insider Risk';             count = $irmCount; note = $irmNote; sectionId = 'Insider_Risk';             checkId = 'IRM-01' }
            [pscustomobject]@{ name = 'Communication Compliance'; count = $ccCount;  note = $ccNote;  sectionId = 'Communication_Compliance'; checkId = 'CC-01' }
        )
    }
}
