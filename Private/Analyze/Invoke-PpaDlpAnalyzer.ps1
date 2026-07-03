# Invoke-PpaDlpAnalyzer.ps1 - analyzer for section 02 (Data Loss Prevention).
# Produces DLP-01..04 per CHECK_CATALOG.md. DLP-01/02/03 assert from readable signals
# (policy mode, locations, endpoint scope). DLP-03 device-onboarded count and DLP-04
# named-entity detector availability are not readable read-only (open items D3/D4), so
# those rows report Verify manually rather than a fabricated value.
# ASCII-only source (Windows PowerShell 5.1). Depends on New-PpaFinding/New-PpaSection.

Set-StrictMode -Off

function Test-PpaDlpEnforcing {
    param([string]$Mode)
    return ($Mode -match '(?i)^enable$|enforce')
}

function Get-PpaSitTierMap {
    # Load the dated E5-gated SIT tier map (Data/dlp-sit-tiers.json). See LIMITATIONS.md.
    param([string]$Path)
    if (-not $Path) {
        $Path = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Data\dlp-sit-tiers.json'
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Invoke-PpaDlpAnalyzer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Raw,
        [datetime]$AsOf = (Get-Date),
        # Parsed Data/license-requirements.json (static annotation map, not detection).
        $LicenseMap,
        # Parsed Data/dlp-sit-tiers.json; loaded from disk if not supplied.
        $SitTierMap
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

    # --- DLP-04: HIPAA template named-entity detectors (dated SIT map, Verify-flavored) ---
    # Without license detection this check cannot assert detectors are inactive on THIS tenant.
    # The dated map (Data/dlp-sit-tiers.json) identifies which referenced SITs are E5-gated
    # named-entity detectors; every such row says "requires E5 - verify tenant tier". Unmapped
    # SITs are 'tier not confirmed' - never a silent OK. See LIMITATIONS.md.
    if (-not $SitTierMap) { $SitTierMap = Get-PpaSitTierMap }
    $sitLookup = @{}
    if ($SitTierMap -and $SitTierMap.sits) { foreach ($s in @($SitTierMap.sits)) { $sitLookup[[string]$s.name] = $s } }
    $mapReviewed = if ($SitTierMap) { [string]$SitTierMap.lastReviewed } else { 'unknown' }

    $lm04 = @(@{ label = 'DLP policy reference'; url = 'https://learn.microsoft.com/en-us/purview/dlp-policy-reference'; tag = 'docs' })
    $hipaaRegex = '(?i)HIPAA|health|ICD|medical|disease|patient'
    $hipaaPolicyNames = @($rules | Where-Object { @($_.sits) -match $hipaaRegex } | ForEach-Object { $_.policyName } | Select-Object -Unique)
    $hipaaSits = @($rules | Where-Object { $hipaaPolicyNames -contains $_.policyName } | ForEach-Object { $_.sits } | Where-Object { $_ } | Select-Object -Unique)

    if ($hipaaSits.Count -eq 0) {
        $findings.Add((New-PpaFinding -Id 'DLP-04' -DomId 'f-dlp-4' -Title 'No HIPAA-template policies detected' -Status 'Informational' `
            -Whyline 'No DLP policy references a HIPAA / medical detector, so template-tiering does not apply.' `
            -Table (New-PpaTable -Columns @('Configuration', 'Setting', 'Status') -Rows @((New-PpaRow -Cells @('HIPAA-template policies', '0') -Status 'Informational'))) -LearnMore $lm04))
    }
    else {
        $rows04 = New-Object System.Collections.Generic.List[object]
        foreach ($sit in $hipaaSits) {
            if ($sitLookup.ContainsKey($sit)) {
                $req = [string]$sitLookup[$sit].requiredLicense
                $rows04.Add((New-PpaRow -Cells @($sit, "Named-entity SIT $mid requires $req $mid verify tenant tier") -Status 'Verify manually'))
            }
            else {
                $rows04.Add((New-PpaRow -Cells @($sit, 'Tier not confirmed read-only') -Status 'Verify manually'))
            }
        }
        # Attach the map-provenance remark to the final row.
        $last = $rows04[$rows04.Count - 1]
        $last | Add-Member -NotePropertyName remark -NotePropertyValue "this tool does not read licensing - confirm which detectors are active at the tenant tier; E5-gated SIT map last reviewed $mapReviewed." -Force

        $findings.Add((New-PpaFinding -Id 'DLP-04' -DomId 'f-dlp-4' -Title 'HIPAA template references named-entity SITs that require E5 - verify tenant tier' -Status 'Verify manually' -Requires (Get-PpaRequirement $LicenseMap 'DLP-04') `
            -Whyline 'The client may believe they have full HIPAA coverage while named-entity detectors are inactive below E5 - confirm at the tenant tier.' `
            -Table (New-PpaTable -Columns @('Detector (SIT)', 'Availability', 'Status') -Rows $rows04.ToArray()) -LearnMore $lm04))
    }

    # --- glance ---
    $enfCount = @($pols | Where-Object { $polInfo[$_.name].enforcing }).Count
    $teamsText = if ($teamsInScope) { 'Teams scoped' } else { 'Teams unscoped' }
    $glance = New-PpaGlance -Name 'Data Loss Prevention' -Metric "$($pols.Count) policies" -Sub "$enfCount enforcing $mid $teamsText"

    return New-PpaSection -Id 'Data_Loss_Prevention' -Title 'Data Loss Prevention' -Group 'Microsoft Information Protection' `
        -GroupIcon 'fas fa-shield-alt' -Glance $glance -Findings $findings.ToArray()
}
