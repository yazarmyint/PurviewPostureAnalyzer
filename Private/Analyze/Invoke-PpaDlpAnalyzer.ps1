# Invoke-PpaDlpAnalyzer.ps1 - analyzer for section 02 (Data Loss Prevention).
# Produces DLP-01..03 per CHECK_CATALOG.md, asserting from readable signals (policy
# mode, locations, endpoint scope). The DLP-03 device-onboarded count is not readable
# read-only (open item D3), so that row reports Verify manually rather than a
# fabricated value. DLP-04 (HIPAA template detector tiering) was RETIRED in Wave 5
# cleanup Part 4 with nothing in its place - see the CHECK_CATALOG.md tombstone; the
# ID is never reused.
# ASCII-only source (Windows PowerShell 5.1). Depends on New-PpaFinding/New-PpaSection.

Set-StrictMode -Off

function Test-PpaDlpEnforcing {
    param([string]$Mode)
    return ($Mode -match '(?i)^enable$|enforce')
}

function Invoke-PpaDlpAnalyzer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Raw,
        [datetime]$AsOf = (Get-Date),
        # Parsed Data/license-requirements.json (static annotation map, not detection).
        $LicenseMap
    )

    $mid   = Get-PpaMidDot
    $pols  = @($Raw.policies.items)
    $rules = @($Raw.rules.items)
    $findings = New-Object System.Collections.Generic.List[object]

    # Per-policy rollups from rules.
    $polInfo = @{}
    foreach ($p in $pols) {
        $pr = @($rules | Where-Object { $_.policyName -eq $p.name })
        $sits = @($pr | ForEach-Object { $_.sits } | Where-Object { $_ } | Select-Object -Unique)
        $polInfo[$p.name] = [pscustomobject]@{
            enforcing    = (Test-PpaDlpEnforcing $p.mode)
            sits         = $sits
            ruleTotal    = $pr.Count
            ruleDisabled = @($pr | Where-Object { $_.disabled }).Count
        }
    }

    # --- DLP-01: policies exist (enforcing vs test) ---
    $lm01 = @(
        @{ label = 'Microsoft Purview portal - Data Loss Prevention'; url = 'https://purview.microsoft.com'; tag = 'portal' }
        @{ label = 'Learn about data loss prevention'; url = 'https://learn.microsoft.com/en-us/purview/dlp-learn-about-dlp'; tag = 'docs' }
    )
    if ($pols.Count -eq 0) {
        $findings.Add((New-PpaFinding -Id 'DLP-01' -DomId 'f-dlp-1' -Title 'No DLP policies configured' -Status 'Improvement' `
            -Whyline 'With no DLP policies, sensitive data can leave the tenant unmonitored.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @((New-PpaRow -Cells @('DLP policies', '0') -Status 'Improvement'))) -LearnMore $lm01))
    }
    else {
        $enfCount = @($pols | Where-Object { $polInfo[$_.name].enforcing }).Count
        $testCount = $pols.Count - $enfCount
        $rows01 = New-Object System.Collections.Generic.List[object]
        foreach ($p in $pols) {
            $info = $polInfo[$p.name]
            $abbr = New-Object System.Collections.Generic.List[string]
            if ($p.locations.exchange)   { $abbr.Add('EXO') }
            if ($p.locations.sharePoint) { $abbr.Add('SPO') }
            if ($p.locations.oneDrive)   { $abbr.Add('ODB') }
            if ($p.locations.teams)      { $abbr.Add('Teams') }
            if ($p.locations.endpoint)   { $abbr.Add('Endpoint') }
            if ($info.enforcing) {
                $remarkCell = if ($abbr.Count -gt 0) { "Enforcing $mid " + (@($abbr) -join ', ') } else { 'Enforcing' }
            }
            elseif ($info.ruleDisabled -gt 0) {
                $remarkCell = "Test mode; $($info.ruleDisabled) of $($info.ruleTotal) rules disabled"
            }
            else {
                $remarkCell = 'Test / simulation mode'
            }
            $rowRemark = $null
            if (-not $info.enforcing -and $p.testModeSince) {
                $since = [datetime]$p.testModeSince
                $rowRemark = "in test mode since $($since.ToString('dd-MMM-yyyy')) - detects but does not block."
            }
            $rows01.Add((New-PpaRow -Cells @($p.name, (@($info.sits) -join ', '), $remarkCell) -Status ($(if ($info.enforcing) { 'OK' } else { 'Improvement' })) -Remark $rowRemark))
        }
        $findings.Add((New-PpaFinding -Id 'DLP-01' -DomId 'f-dlp-1' -Title "$($pols.Count) DLP policies exist ($enfCount enforcing, $testCount in test)" -Status 'Informational' `
            -Whyline "Policy count alone overstates protection; test-mode policies detect but don't block. Each policy:" `
            -Table (New-PpaTable -Columns @('DLP Policy', 'Sensitive Information Type', 'Remarks', 'Status') -Rows $rows01.ToArray()) -LearnMore $lm01))
    }

    # --- DLP-02: Teams scope ---
    $locName = [ordered]@{ exchange = 'Exchange Online'; sharePoint = 'SharePoint Online'; oneDrive = 'OneDrive'; teams = 'Microsoft Teams' }
    $rows02 = New-Object System.Collections.Generic.List[object]
    foreach ($key in $locName.Keys) {
        $count = @($pols | Where-Object { $_.locations.$key }).Count
        $inScope = $count -gt 0
        $display = if ($count -eq $pols.Count -and $count -gt 0) { 'Yes (all policies)' } elseif ($inScope) { 'Yes' } else { 'No' }
        $rows02.Add((New-PpaRow -Cells @($locName[$key], $display) -Status ($(if ($inScope) { 'OK' } else { 'Improvement' }))))
    }
    $teamsInScope = @($pols | Where-Object { $_.locations.teams }).Count -gt 0
    $findings.Add((New-PpaFinding -Id 'DLP-02' -DomId 'f-dlp-2' -Title ($(if ($teamsInScope) { 'Teams is in scope' } else { 'Teams is not in scope' })) -Status ($(if ($teamsInScope) { 'OK' } else { 'Improvement' })) -Requires (Get-PpaRequirement $LicenseMap 'DLP-02') `
        -Whyline "Sensitive data shared in Teams bypasses DLP entirely when Teams isn't a policy location." `
        -Table (New-PpaTable -Columns @('Location', 'In scope', 'Status') -Rows $rows02.ToArray()) `
        -LearnMore @(@{ label = 'Use DLP with Microsoft Teams'; url = 'https://learn.microsoft.com/en-us/purview/dlp-microsoft-teams'; tag = 'docs' })))

    # --- DLP-03: Endpoint DLP (device count not readable read-only -> Verify manually) ---
    $endpointCount = @($pols | Where-Object { $_.locations.endpoint }).Count
    $rows03 = @(
        New-PpaRow -Cells @('Devices onboarded', 'Not readable read-only') -Status 'Verify manually'
        New-PpaRow -Cells @('Endpoint locations in policy', ($(if ($endpointCount -gt 0) { "$endpointCount policies" } else { 'None' }))) -Status ($(if ($endpointCount -gt 0) { 'OK' } else { 'Improvement' }))
    )
    $findings.Add((New-PpaFinding -Id 'DLP-03' -DomId 'f-dlp-3' -Title ($(if ($endpointCount -gt 0) { 'Endpoint DLP is configured' } else { 'Endpoint DLP is not configured' })) -Status ($(if ($endpointCount -gt 0) { 'OK' } else { 'Improvement' })) -Requires (Get-PpaRequirement $LicenseMap 'DLP-03') `
        -Whyline "Without Endpoint DLP there's no control over copy-to-USB, print, or cloud-upload egress on managed devices." `
        -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows $rows03) `
        -LearnMore @(@{ label = 'Learn about Endpoint DLP'; url = 'https://learn.microsoft.com/en-us/purview/endpoint-dlp-learn-about'; tag = 'docs' })))

    # (DLP-04, the HIPAA template detector-tiering check, was emitted here until it
    # was RETIRED in Wave 5 cleanup Part 4 - removed with nothing in its place. The
    # industry-neutral signals it might have carried already live in DLP-01 remarks
    # (enforcement mode), DLP-02 (workload coverage) and DLP-03 (endpoint posture).)

    # --- glance ---
    $enfCount = @($pols | Where-Object { $polInfo[$_.name].enforcing }).Count
    $teamsText = if ($teamsInScope) { 'Teams scoped' } else { 'Teams unscoped' }
    $glance = New-PpaGlance -Name 'Data Loss Prevention' -Metric "$($pols.Count) policies" -Sub "$enfCount enforcing $mid $teamsText"

    return New-PpaSection -Id 'Data_Loss_Prevention' -Title 'Data Loss Prevention' -Group 'Microsoft Information Protection' `
        -GroupIcon 'fas fa-shield-alt' -Glance $glance -Findings $findings.ToArray()
}
