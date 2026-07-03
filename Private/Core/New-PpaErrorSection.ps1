# New-PpaErrorSection.ps1 - a placeholder section for a workload whose collector or
# analyzer failed. Graceful degradation: one section failing never fails the run; the
# error is surfaced in the report as a Verify-manually finding, never swallowed.
# ASCII-only source. Depends on New-PpaFinding/New-PpaSection.

Set-StrictMode -Off

function New-PpaErrorSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Group,
        [Parameter(Mandatory = $true)][string]$GroupIcon,
        [string]$GroupTag,
        [string]$Message = 'The collector did not complete.'
    )

    $domId = 'f-' + ($Id.ToLower() -replace '[^a-z0-9]', '-') + '-err'
    $finding = New-PpaFinding -Id "$Id-ERR" -DomId $domId -Title "$Title could not be assessed this session" -Status 'Verify manually' `
        -Whyline 'The collector for this section did not complete, so its posture was not evaluated. Assess this area manually.' `
        -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
            New-PpaRow -Cells @('Collector', 'Did not complete') -Status 'Verify manually' -Remark $Message
        )) -LearnMore @()

    $glance = New-PpaGlance -Name $Title -Status 'Verify manually' -Metric 'n/a' -Sub 'collector error'

    $params = @{ Id = $Id; Title = $Title; Group = $Group; GroupIcon = $GroupIcon; Glance = $glance; Findings = @($finding) }
    if (-not [string]::IsNullOrEmpty($GroupTag)) { $params.GroupTag = $GroupTag }
    return New-PpaSection @params
}
