# New-PpaFinding.ps1 - factories for the finding object and its drill-down table.
# The finding is the atom of the report (PLAN.md section 4). Analyzers call these in
# Phase 3; using them guarantees a valid shape and a valid status.
# ASCII-only source (Windows PowerShell 5.1). Depends on PpaStatus.ps1 (Test-PpaStatus).

Set-StrictMode -Off

function New-PpaRow {
    # One row of a drill-down table. Cells are the non-status columns; Status is the
    # row-level display status; Remark renders as a full-width note after this row.
    # Cells may be empty strings - real tenant data has optional fields (empty ParentId,
    # zero rules behind a policy), and mandatory [string[]] binding would otherwise throw
    # "Cannot bind argument ... empty string". Empty cells render as a placeholder dash.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Cells,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Remark,
        [switch]$Indent
    )
    if (-not (Test-PpaStatus $Status)) {
        throw "New-PpaRow: invalid status '$Status'. Must be one of: $((Get-PpaStatusOrder) -join ', ')"
    }
    # Normalize nulls to empty strings so downstream consumers see a consistent shape.
    $o = [ordered]@{ cells = @(@($Cells) | ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } }); status = $Status }
    if ($PSBoundParameters.ContainsKey('Remark') -and -not [string]::IsNullOrEmpty($Remark)) { $o.remark = $Remark }
    if ($Indent) { $o.indent = $true }
    return [pscustomobject]$o
}

function New-PpaTable {
    # A drill-down table. Columns includes the trailing 'Status' header; each row's
    # cells cover the columns except that trailing Status column.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Columns,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows
    )
    return [pscustomobject][ordered]@{ columns = @($Columns); rows = @($Rows) }
}

function New-PpaFinding {
    # A single finding. Its status is the ONLY status that rolls up into the section
    # and Solutions Summary counts. Table may be $null (advisory findings, e.g. IRM-02).
    # Requires is the static license ANNOTATION (from Data/license-requirements.json) -
    # what tier the feature needs per the Purview service description. It is never a
    # claim about the tenant's licensing; the tool does not read subscriptions.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$DomId,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Whyline,
        $Table = $null,
        $LearnMore = @(),
        [string]$Requires
    )
    if (-not (Test-PpaStatus $Status)) {
        throw "New-PpaFinding: invalid status '$Status'. Must be one of: $((Get-PpaStatusOrder) -join ', ')"
    }
    $o = [ordered]@{
        id        = $Id
        domId     = $DomId
        title     = $Title
        status    = $Status
        whyline   = $Whyline
        table     = $Table
        learnmore = @($LearnMore)
    }
    if ($PSBoundParameters.ContainsKey('Requires') -and -not [string]::IsNullOrEmpty($Requires)) { $o.requires = $Requires }
    return [pscustomobject]$o
}
