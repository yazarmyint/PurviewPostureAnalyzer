# Get-PpaDlp.ps1 - collector for section 02 (Data Loss Prevention).
# Reads Get-DlpCompliancePolicy (.Mode, *Location) and Get-DlpComplianceRule (SIT names,
# Disabled) - read-only. Projects to client-safe metadata: policy names, enforce/test
# mode, which locations are in scope (booleans), and SIT NAMES only (never content or
# matched values). ASCII-only source. Depends on Invoke-PpaReadCmdlet.ps1.

Set-StrictMode -Off

function Test-PpaLocationInScope {
    # A DLP *Location property is in scope when it has any value (often the token 'All').
    param($Location)
    if ($null -eq $Location) { return $false }
    return (@($Location).Count -gt 0)
}

function Get-PpaDlp {
    [CmdletBinding()]
    param()

    $rawPols  = Invoke-PpaReadCmdlet -Name 'Get-DlpCompliancePolicy'
    $rawRules = Invoke-PpaReadCmdlet -Name 'Get-DlpComplianceRule'

    $policyItems = foreach ($p in @($rawPols.Data)) {
        [pscustomobject]@{
            name         = [string]$p.Name
            guid         = Get-PpaOptionalGuid $p
            mode         = [string]$p.Mode
            locations    = [pscustomobject]@{
                exchange   = (Test-PpaLocationInScope $p.ExchangeLocation)
                sharePoint = (Test-PpaLocationInScope $p.SharePointLocation)
                oneDrive   = (Test-PpaLocationInScope $p.OneDriveLocation)
                teams      = (Test-PpaLocationInScope $p.TeamsLocation)
                endpoint   = (Test-PpaLocationInScope $p.EndpointDlpLocation)
            }
            testModeSince = ConvertTo-PpaIso8601 $p.LastStatusChangeDate
        }
    }

    $ruleItems = foreach ($r in @($rawRules.Data)) {
        $sitNames = @()
        foreach ($sit in @($r.ContentContainsSensitiveInformation)) {
            if ($sit -and $sit.Name) { $sitNames += [string]$sit.Name }
        }
        $parentPolicy = if ($r.ParentPolicyName) { [string]$r.ParentPolicyName } else { [string]$r.Policy }
        [pscustomobject]@{
            policyName = $parentPolicy
            name       = [string]$r.Name
            guid       = Get-PpaOptionalGuid $r
            disabled   = [bool]($r.Disabled -eq $true)
            sits       = @($sitNames)
        }
    }

    return [pscustomobject]@{
        outcome  = Resolve-PpaCollectorOutcome -ReadStatuses @($rawPols.Status, $rawRules.Status) -ItemCount (@($policyItems).Count + @($ruleItems).Count)
        policies = [pscustomobject]@{ status = $rawPols.Status;  error = $rawPols.Error;  items = @($policyItems) }
        rules    = [pscustomobject]@{ status = $rawRules.Status; error = $rawRules.Error; items = @($ruleItems) }
    }
}
