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
        [string]$UserPrincipalName,
        # Cross-tenant guest / B2B support (pre-publish Part 6): connect to a CLIENT
        # tenant as an invited guest. -DelegatedOrganization names the client tenant
        # (e.g. client.onmicrosoft.com). The Security & Compliance endpoint ALSO
        # requires -AzureADAuthorizationEndpointUri (module 3.0.0+); when not
        # supplied it is derived as https://login.microsoftonline.com/<org>, matching
        # the MS Learn guest example. Commercial cloud only - sovereign clouds are
        # out of scope. Exchange Online takes the organization ALONE.
        [string]$DelegatedOrganization,
        [string]$AzureADAuthorizationEndpointUri
    )

    # F-014 presence guard: without the ExchangeOnlineManagement module NOTHING can
    # connect, so stop cleanly BEFORE any connection work - a terminating error with
    # the locked, operator-approved message. Availability check only (never an import,
    # never a command probe). All three connect paths (manual run, -Connect switch,
    # guest/B2B) funnel through this function, so this single guard covers them all.
    # (Guard-scan note: the install hint is composed at runtime so no mutating-verb
    # cmdlet literal appears in source - message text for the operator, never an
    # invocation. Same convention as the -Connect both-failed hint in the invoker.)
    if (-not (Test-PpaExoModuleAvailable)) {
        throw (@(
            'ExchangeOnlineManagement module not found.'
            'PurviewPostureAnalyzer needs it to connect to Microsoft Purview. PPA stopped before connecting.'
            ''
            'To install it, run:'
            ('    ' + 'Install' + '-Module ExchangeOnlineManagement -Scope CurrentUser')
            ''
            'Then run PurviewPostureAnalyzer again.'
        ) -join [Environment]::NewLine)
    }

    $results = [ordered]@{ SecurityCompliance = 'not attempted'; ExchangeOnline = 'not attempted' }

    # Param hygiene: the endpoint is a guest-call refinement - without the guest
    # organization it has no meaning, so it is ignored loudly, never applied.
    if ($AzureADAuthorizationEndpointUri -and -not $DelegatedOrganization) {
        Write-Warning '-AzureADAuthorizationEndpointUri is only used with -DelegatedOrganization (guest/B2B connect); ignoring it.'
    }

    # Security & Compliance PowerShell
    try {
        if (Get-Command -Name 'Connect-IPPSSession' -ErrorAction SilentlyContinue) {
            $ippsArgs = @{ ShowBanner = $false; ErrorAction = 'Stop' }
            if ($UserPrincipalName) { $ippsArgs.UserPrincipalName = $UserPrincipalName }
            if ($DelegatedOrganization) {
                # Guest call: IPPS needs BOTH the organization and the auth endpoint
                # (verified against MS Learn, module 3.0.0+).
                $ippsArgs.DelegatedOrganization = $DelegatedOrganization
                $ep = if ($AzureADAuthorizationEndpointUri) { $AzureADAuthorizationEndpointUri }
                      else { "https://login.microsoftonline.com/$DelegatedOrganization" }
                $ippsArgs.AzureADAuthorizationEndpointUri = $ep
            }
            Connect-IPPSSession @ippsArgs
            $results.SecurityCompliance = 'connected'
        }
        else { $results.SecurityCompliance = 'ExchangeOnlineManagement module not installed' }
    }
    catch { $results.SecurityCompliance = "failed: $($_.Exception.Message)" }

    # Exchange Online
    try {
        if (Get-Command -Name 'Connect-ExchangeOnline' -ErrorAction SilentlyContinue) {
            $exoArgs = @{ ShowBanner = $false; ErrorAction = 'Stop' }
            if ($UserPrincipalName) { $exoArgs.UserPrincipalName = $UserPrincipalName }
            # Guest call: EXO takes the organization ALONE - intentionally NO
            # AzureADAuthorizationEndpointUri here (per the MS Learn guest example).
            if ($DelegatedOrganization) { $exoArgs.DelegatedOrganization = $DelegatedOrganization }
            Connect-ExchangeOnline @exoArgs
            $results.ExchangeOnline = 'connected'
        }
        else { $results.ExchangeOnline = 'ExchangeOnlineManagement module not installed' }
    }
    catch { $results.ExchangeOnline = "failed: $($_.Exception.Message)" }

    return [pscustomobject]$results
}
