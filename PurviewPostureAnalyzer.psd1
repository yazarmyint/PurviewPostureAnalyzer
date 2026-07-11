@{
    RootModule        = 'PurviewPostureAnalyzer.psm1'
    ModuleVersion     = '2.1.0'
    GUID              = '08016980-865c-4ab2-8df2-4c60e235189f'
    Author            = 'Yazar Myint'
    CompanyName       = 'Community'
    Copyright         = 'Licensed under the MIT License. Not an official Microsoft product.'
    Description       = 'Read-only Microsoft Purview posture analyzer (modernized CAMP). Reads configuration metadata across Sensitivity Labels, DLP, Retention, Insider Risk, Audit, eDiscovery, Communication Compliance and DSPM for AI, and produces an HTML report (primary) plus a JSON export. Collectors call Get-* only; no tenant configuration is created, modified or deleted, and no content is collected. Requires the ExchangeOnlineManagement module for the two read-only sessions (Connect-IPPSSession and Connect-ExchangeOnline); without it, PPA stops before connecting.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Connect-PurviewPostureSession',
        'Disconnect-PurviewPostureSession',
        'Invoke-PurviewPostureAnalyzer'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Microsoft365', 'Purview', 'Compliance', 'DLP', 'ReadOnly', 'CAMP', 'Security')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/yazarmyint/PurviewPostureAnalyzer'
            ReleaseNotes = 'v2.1.0: one-command runs via the opt-in -Connect / -Disconnect / -Show switches (-UserPrincipalName pre-fills the sign-in); client-branded reports via -LogoPath (image embedded as a base64 data URI, the report stays self-contained and offline); cross-tenant B2B guest assessments via -DelegatedOrganization with optional -AzureADAuthorizationEndpointUri; clearer findings - GUID references resolved to display names across sensitivity-label policies, retention rule references, and DSPM for AI label conditions. First PowerShell Gallery release.'
        }
    }
}
