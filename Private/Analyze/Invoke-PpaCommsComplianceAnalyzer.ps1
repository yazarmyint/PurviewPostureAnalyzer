# Invoke-PpaCommsComplianceAnalyzer.ps1 - analyzer for section 07 (Communication Compliance).
# Assume-E5 model (decision D9): verdicts from Get-SupervisoryReviewPolicyV2 evidence like
# any E3 workload - policies returned -> inventory; genuinely empty -> a normal Improvement;
# unreadable -> Verify manually. The 'Requires' annotation rides alongside the verdict.
# ASCII-only source. Depends on New-PpaFinding/New-PpaSection/Get-PpaRequirement.

Set-StrictMode -Off

function Invoke-PpaCommsComplianceAnalyzer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Raw,
        $LicenseMap
    )

    $mid = Get-PpaMidDot
    $count = $Raw.policies.count          # $null when the read did not complete
    $req = Get-PpaRequirement $LicenseMap 'CC-01'
    $findings = New-Object System.Collections.Generic.List[object]
    $lm = @(@{ label = 'Learn about Communication Compliance'; url = 'https://learn.microsoft.com/en-us/purview/communication-compliance'; tag = 'docs' })

    if ($null -eq $count) {
        $findings.Add((New-PpaFinding -Id 'CC-01' -DomId 'f-cc-1' -Title 'Communication Compliance inventory not readable this session' -Status 'Verify manually' -Requires $req `
            -Whyline 'Supervisory-review policies could not be enumerated this session - confirm coverage in the Purview portal.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Communication Compliance policies', 'Not readable this session') -Status 'Verify manually'
            )) -LearnMore $lm))
    }
    elseif ($count -eq 0) {
        $findings.Add((New-PpaFinding -Id 'CC-01' -DomId 'f-cc-1' -Title 'No Communication Compliance policies configured' -Status 'Improvement' -Requires $req `
            -Whyline 'No supervisory-review policy is capturing communications - relevant wherever regulatory supervision of communications is in scope.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Communication Compliance policies', '0') -Status 'Improvement'
            )) -LearnMore $lm))
    }
    else {
        $findings.Add((New-PpaFinding -Id 'CC-01' -DomId 'f-cc-1' -Title "Communication Compliance in use - $count policies" -Status 'Informational' -Requires $req `
            -Whyline 'Supervisory-review policies are capturing communications for review.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
                New-PpaRow -Cells @('Communication Compliance policies', [string]$count) -Status 'Informational'
            )) -LearnMore $lm))
    }

    $metric = if ($null -eq $count) { 'not readable' } else { "$count policies" }
    $glance = New-PpaGlance -Name 'Comms Compliance' -Metric $metric -Sub 'requires E5'

    return New-PpaSection -Id 'Communication_Compliance' -Title 'Communication Compliance' -Group 'Insider Risk' `
        -GroupIcon 'fas fa-user-secret' -Glance $glance -Findings $findings.ToArray()
}
