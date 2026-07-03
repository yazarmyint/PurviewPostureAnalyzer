# Connect-PurviewPostureSession.ps1 - opens the two read-only sessions the analyzer uses:
#   Security & Compliance PowerShell (Connect-IPPSSession) - labels, DLP, retention, IRM,
#     comms compliance, eDiscovery, DSPM-for-AI (Copilot-location) policies
#   Exchange Online (Connect-ExchangeOnline) - audit config, organization config
#
# No Microsoft Graph: the tool never reads licensing or directory data, so there is no
# Graph module requirement and no admin-consent prompt (PLAN.md decision D9). License
# context in the report is a static annotation from Data/license-requirements.json.
#
# These are interactive sign-ins. This module never mutates the tenant; the Connect-*
# cmdlets only establish sessions. ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function Connect-PurviewPostureSession {
    [CmdletBinding()]
    param(
        [string]$UserPrincipalName
    )

    $results = [ordered]@{ SecurityCompliance = 'not attempted'; ExchangeOnline = 'not attempted' }

    # Security & Compliance PowerShell
    try {
        if (Get-Command -Name 'Connect-IPPSSession' -ErrorAction SilentlyContinue) {
            if ($UserPrincipalName) { Connect-IPPSSession -UserPrincipalName $UserPrincipalName -ShowBanner:$false -ErrorAction Stop }
            else { Connect-IPPSSession -ShowBanner:$false -ErrorAction Stop }
            $results.SecurityCompliance = 'connected'
        }
        else { $results.SecurityCompliance = 'ExchangeOnlineManagement module not installed' }
    }
    catch { $results.SecurityCompliance = "failed: $($_.Exception.Message)" }

    # Exchange Online
    try {
        if (Get-Command -Name 'Connect-ExchangeOnline' -ErrorAction SilentlyContinue) {
            if ($UserPrincipalName) { Connect-ExchangeOnline -UserPrincipalName $UserPrincipalName -ShowBanner:$false -ErrorAction Stop }
            else { Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop }
            $results.ExchangeOnline = 'connected'
        }
        else { $results.ExchangeOnline = 'ExchangeOnlineManagement module not installed' }
    }
    catch { $results.ExchangeOnline = "failed: $($_.Exception.Message)" }

    return [pscustomobject]$results
}
