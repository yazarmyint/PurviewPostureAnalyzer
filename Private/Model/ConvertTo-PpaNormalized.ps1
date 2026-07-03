# ConvertTo-PpaNormalized.ps1 - the assemble stage of the pipeline (PLAN.md section 2).
# Takes the collected/analyzed pieces (meta, licensing, per-section findings,
# observations) and produces the single normalized object that both the HTML renderer
# and the JSON export consume. Counts and the at-a-glance headline are computed here,
# never hand-authored. ASCII-only source. Depends on PpaStatus.ps1.

Set-StrictMode -Off

function ConvertTo-PpaNormalized {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Meta,
        [Parameter(Mandatory = $true)] $Licensing,
        [Parameter(Mandatory = $true)] $Sections,
        $Observations = @()
    )

    $order    = Get-PpaStatusOrder
    $sections = @($Sections)

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
        summary      = [pscustomobject][ordered]@{ totals = [pscustomobject]$totals; groups = $groupsOut.ToArray() }
        sections     = $secOut.ToArray()
        observations = @($Observations)
    }
}
