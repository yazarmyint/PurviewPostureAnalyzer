# ConvertTo-PpaNormalized.ps1 - the assemble stage of the pipeline (PLAN.md section 2).
# Takes the collected/analyzed pieces (meta, licensing, and per-section findings)
# and produces the single normalized object that both the HTML renderer
# and the JSON export consume. Counts and the at-a-glance headline are computed here,
# never hand-authored. ASCII-only source. Depends on PpaStatus.ps1.

Set-StrictMode -Off

function Get-PpaCanonicalSectionOrder {
    # THE canonical solution order (Wave 5 cleanup Part 5, Option B signed off).
    # Single source for the report body and - via the first-appearance grouping
    # below - the Solutions Summary; the coverage matrix column axis is defined in
    # Get-PpaCoverageModel and pinned to this sequence by the three-surface
    # guardrail test in Tests/Coverage.Tests.ps1. Section IDs only - titles are
    # never touched here.
    return @(
        'Sensitivity_Labels'
        'Data_Loss_Prevention'
        'DSPM_for_AI'
        'Retention'
        'Insider_Risk'
        'Communication_Compliance'
        'Audit'
        'eDiscovery'
    )
}

function ConvertTo-PpaNormalized {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Meta,
        [Parameter(Mandatory = $true)] $Licensing,
        [Parameter(Mandatory = $true)] $Sections,
        # Wave 4 Part D: the CoverageModel (pure projection); null renders no matrix.
        $Coverage = $null
    )

    $order    = Get-PpaStatusOrder
    $sections = @($Sections)

    # Wave 5 cleanup Part 5: canonical DISPLAY order, applied at assemble time only.
    # The orchestrator hands the analyze-order sections to New-PpaSnapshotModel
    # before this function runs, so snapshot content (findings order, sectionsRun)
    # never reorders - a pure display change stays out of delta mode. Sections with
    # ids outside the canonical list (error stubs, tests) keep arrival order after
    # the canonical ones; subsets (run profiles) keep canonical relative order.
    $canon   = @(Get-PpaCanonicalSectionOrder)
    $known   = New-Object System.Collections.Generic.List[object]
    $unknown = New-Object System.Collections.Generic.List[object]
    foreach ($id in $canon) {
        foreach ($sec in $sections) { if ([string]$sec.id -eq $id) { $known.Add($sec) } }
    }
    foreach ($sec in $sections) { if ($canon -notcontains [string]$sec.id) { $unknown.Add($sec) } }
    $sections = @($known.ToArray() + $unknown.ToArray())

    # Per-section: resolve glance (explicit status wins; otherwise the precedence
    # headline) and attach computed counts.
    $secOut = New-Object System.Collections.Generic.List[object]
    foreach ($sec in $sections) {
        $counts = Get-PpaSectionCounts $sec
        $g      = $sec.glance

        $glanceStatus = if ($g -and $g.status) { [string]$g.status } else { Get-PpaGlanceHeadline $sec }
        $glanceName   = if ($g -and $g.name)   { [string]$g.name }   else { [string]$sec.title }
        $glanceMetric = if ($g) { [string]$g.metric } else { '' }
        $glanceSub    = if ($g) { [string]$g.sub }    else { '' }

        $secObj = [ordered]@{
            id        = [string]$sec.id
            title     = [string]$sec.title
            group     = [string]$sec.group
            groupIcon = [string]$sec.groupIcon
        }
        if ($sec.groupTag) { $secObj.groupTag = [string]$sec.groupTag }
        $secObj.glance    = [pscustomobject][ordered]@{ status = $glanceStatus; name = $glanceName; metric = $glanceMetric; sub = $glanceSub }
        $secObj.counts    = [pscustomobject]$counts
        $secObj.findings  = @($sec.findings)

        $secOut.Add([pscustomobject]$secObj)
    }

    # Grouped summary (group order = first appearance) + all-solutions totals.
    $groupOrder = New-Object System.Collections.Generic.List[string]
    $groupMap   = @{}
    $groupMeta  = @{}
    $totals     = [ordered]@{ 'OK'=0; 'Improvement'=0; 'Recommendation'=0; 'Informational'=0; 'Verify manually'=0 }

    foreach ($sec in $secOut) {
        $gname = [string]$sec.group
        if (-not $groupMap.ContainsKey($gname)) {
            $groupMap[$gname]  = New-Object System.Collections.Generic.List[object]
            $groupMeta[$gname] = [pscustomobject]@{ icon = [string]$sec.groupIcon; tag = [string]$sec.groupTag }
            $groupOrder.Add($gname)
        }
        $groupMap[$gname].Add($sec)
        foreach ($st in $order) { $totals[$st] = [int]$totals[$st] + [int]$sec.counts.$st }
    }

    $groupsOut = New-Object System.Collections.Generic.List[object]
    foreach ($gname in $groupOrder) {
        $children = New-Object System.Collections.Generic.List[object]
        foreach ($sec in $groupMap[$gname]) {
            $children.Add([pscustomobject][ordered]@{ id = $sec.id; title = $sec.title; counts = $sec.counts })
        }
        $groupsOut.Add([pscustomobject][ordered]@{
            name     = $gname
            icon     = $groupMeta[$gname].icon
            tag      = $groupMeta[$gname].tag
            sections = $children.ToArray()
        })
    }

    return [pscustomobject][ordered]@{
        meta         = $Meta
        licensing    = $Licensing
        coverage     = $Coverage
        summary      = [pscustomobject][ordered]@{ totals = [pscustomobject]$totals; groups = $groupsOut.ToArray() }
        sections     = $secOut.ToArray()
    }
}
