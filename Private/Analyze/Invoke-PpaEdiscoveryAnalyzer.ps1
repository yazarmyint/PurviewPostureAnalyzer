# Invoke-PpaEdiscoveryAnalyzer.ps1 - analyzer for section 06 (eDiscovery).
# Evidence-only: ED-01 inventories Get-ComplianceCase results (no maturity judgment);
# ED-02 is annotation-only - Premium availability depends on tier, which this tool does
# not read. ASCII-only source. Depends on New-PpaFinding/New-PpaSection/Get-PpaRequirement.

Set-StrictMode -Off

function Invoke-PpaEdiscoveryAnalyzer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Raw,
        $LicenseMap
    )

    $mid = Get-PpaMidDot
    $cases = @($Raw.cases.items)
    $findings = New-Object System.Collections.Generic.List[object]

    # --- ED-01: cases (inventory) ---
    $lm01 = @(@{ label = 'Learn about eDiscovery'; url = 'https://learn.microsoft.com/en-us/purview/ediscovery'; tag = 'docs' })
    if ($cases.Count -eq 0) {
        $findings.Add((New-PpaFinding -Id 'ED-01' -DomId 'f-ed-1' -Title 'No eDiscovery cases' -Status 'Informational' `
            -Whyline 'Case existence is reported for inventory only - no judgment on process maturity.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @((New-PpaRow -Cells @('eDiscovery cases', '0') -Status 'Informational'))) -LearnMore $lm01))
    }
    else {
        $rows01 = foreach ($c in $cases) { New-PpaRow -Cells @($c.name, $c.caseStatus) -Status 'Informational' }
        $findings.Add((New-PpaFinding -Id 'ED-01' -DomId 'f-ed-1' -Title "eDiscovery in use - $($cases.Count) cases" -Status 'Informational' `
            -Whyline 'Case existence is reported for inventory only - no judgment on process maturity.' `
            -Table (New-PpaTable -Columns @('Case Name', 'Case Status', 'Status') -Rows @($rows01)) -LearnMore $lm01))
    }

    # --- ED-02: eDiscovery (Premium) usage - not readable this session; tier annotation rides along ---
    $findings.Add((New-PpaFinding -Id 'ED-02' -DomId 'f-ed-2' -Title 'eDiscovery (Premium) usage not assessed' -Status 'Informational' -Requires (Get-PpaRequirement $LicenseMap 'ED-02') `
        -Whyline 'Premium bounds what the client can do in-platform for legal holds, analytics and review sets; premium case usage is not assessed by this session.' `
        -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @(
            New-PpaRow -Cells @('eDiscovery Premium (hold, analytics, review sets)', 'Not assessed this session') -Status 'Informational'
        )) `
        -LearnMore @(@{ label = 'eDiscovery capabilities by tier'; url = 'https://learn.microsoft.com/en-us/purview/ediscovery'; tag = 'docs' })))

    # --- glance ---
    $glance = New-PpaGlance -Name 'eDiscovery' -Metric "$($cases.Count) cases" -Sub "Premium requires E5"

    return New-PpaSection -Id 'eDiscovery' -Title 'eDiscovery' -Group 'Discovery & Response' `
        -GroupIcon 'fas fa-search' -Glance $glance -Findings $findings.ToArray()
}
