@{
    RootModule        = 'PurviewPostureAnalyzer.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = '08016980-865c-4ab2-8df2-4c60e235189f'
    Author            = 'CAMP v2 contributors'
    CompanyName       = 'Community'
    Copyright         = 'Licensed under the MIT License. Not an official Microsoft product.'
    Description       = 'Read-only Microsoft Purview posture analyzer (modernized CAMP). Reads configuration metadata across Sensitivity Labels, DLP, Retention, Insider Risk, Audit, eDiscovery, Communication Compliance and DSPM for AI, and produces an HTML report (primary) plus a JSON export. Collectors call Get-* only; no tenant configuration is created, modified or deleted, and no content is collected.'
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
            ProjectUri   = 'https://github.com/OfficeDev/Configuration-Analyzer-for-Microsoft-Purview'
            ReleaseNotes = 'v2.0 rebuild: report-first HTML deliverable, five-status model (OK / Improvement / Recommendation / Informational / Verify manually), read-only guard, and eight Purview workload sections.'
        }
    }
}
