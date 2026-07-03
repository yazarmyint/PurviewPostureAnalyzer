# New-PpaSection.ps1 - factory for a section object (one workload card).
# Analyzers return one of these; ConvertTo-PpaNormalized assembles them.
# Glance.status may be omitted - the assemble stage computes the headline then.
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function New-PpaGlance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Metric = '',
        [string]$Sub = '',
        [string]$Status
    )
    $o = [ordered]@{ }
    if ($PSBoundParameters.ContainsKey('Status') -and -not [string]::IsNullOrEmpty($Status)) { $o.status = $Status }
    $o.name   = $Name
    $o.metric = $Metric
    $o.sub    = $Sub
    return [pscustomobject]$o
}

function New-PpaSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Group,
        [Parameter(Mandatory = $true)][string]$GroupIcon,
        [string]$GroupTag,
        [Parameter(Mandatory = $true)]$Glance,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Findings
    )
    $o = [ordered]@{ id = $Id; title = $Title; group = $Group; groupIcon = $GroupIcon }
    if ($PSBoundParameters.ContainsKey('GroupTag') -and -not [string]::IsNullOrEmpty($GroupTag)) { $o.groupTag = $GroupTag }
    $o.glance   = $Glance
    $o.findings = @($Findings)
    return [pscustomobject]$o
}
