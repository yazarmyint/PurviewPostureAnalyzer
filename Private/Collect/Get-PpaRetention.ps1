# Get-PpaRetention.ps1 - collector for section 03 (Retention & Records).
# Reads Get-RetentionCompliancePolicy (scope + locations), Get-RetentionComplianceRule
# (labels + auto-apply condition) and Get-AdaptiveScope (count) - all read-only. Projects
# to client-safe metadata: policy/label NAMES, scope type, location TYPES, and whether an
# auto-apply condition exists (never the condition contents/query).
# ASCII-only source. Depends on Invoke-PpaReadCmdlet.ps1.
#
# NOTE: the exact rule->label linkage and auto-apply property vary by tenant; the
# projection below is best-effort and should be confirmed against a live tenant.

Set-StrictMode -Off

function Get-PpaRetention {
    [CmdletBinding()]
    param()

    $rawPols   = Invoke-PpaReadCmdlet -Name 'Get-RetentionCompliancePolicy'
    $rawRules  = Invoke-PpaReadCmdlet -Name 'Get-RetentionComplianceRule'
    $rawScopes = Invoke-PpaReadCmdlet -Name 'Get-AdaptiveScope'

    $policyItems = foreach ($p in @($rawPols.Data)) {
        $locs = New-Object System.Collections.Generic.List[string]
        if (@($p.SharePointLocation).Count   -gt 0) { $locs.Add('SharePoint') }
        if (@($p.ExchangeLocation).Count     -gt 0) { $locs.Add('Exchange') }
        if (@($p.ModernGroupLocation).Count  -gt 0) { $locs.Add('Groups') }
        if (@($p.OneDriveLocation).Count     -gt 0) { $locs.Add('OneDrive') }
        $ruleLabels = @($rawRules.Data | Where-Object { $_.Policy -eq $p.Guid -or $_.ParentPolicyName -eq $p.Name } | ForEach-Object { [string]$_.Name })
        [pscustomobject]@{
            name      = [string]$p.Name
            guid      = Get-PpaOptionalGuid $p
            adaptive  = (@($p.AdaptiveScopeLocation).Count -gt 0)
            locations = @($locs)
            # Part D matrix grounding (documented-only shape, additive; the token
            # array above stays the analyzer contract). Includes the documented
            # Teams retention locations not surfaced in the legacy tokens.
            locationScope = [pscustomobject]@{
                exchange     = (Get-PpaLocationScopeToken $p.ExchangeLocation)
                sharePoint   = (Get-PpaLocationScopeToken $p.SharePointLocation)
                oneDrive     = (Get-PpaLocationScopeToken $p.OneDriveLocation)
                groups       = (Get-PpaLocationScopeToken $p.ModernGroupLocation)
                teamsChannel = (Get-PpaLocationScopeToken $p.TeamsChannelLocation)
                teamsChat    = (Get-PpaLocationScopeToken $p.TeamsChatLocation)
            }
            labels    = @($ruleLabels)
        }
    }

    $labelItems = foreach ($r in @($rawRules.Data)) {
        $auto = (-not [string]::IsNullOrEmpty([string]$r.ContentMatchQuery)) -or (@($r.ContentContainsSensitiveInformation).Count -gt 0)
        [pscustomobject]@{ name = [string]$r.Name; guid = Get-PpaOptionalGuid $r; autoApply = [bool]$auto }
    }

    return [pscustomobject]@{
        outcome        = Resolve-PpaCollectorOutcome -ReadStatuses @($rawPols.Status, $rawRules.Status, $rawScopes.Status) -ItemCount (@($policyItems).Count + @($labelItems).Count + @($rawScopes.Data).Count)
        policies       = [pscustomobject]@{ status = $rawPols.Status;  error = $rawPols.Error;  items = @($policyItems) }
        labels         = [pscustomobject]@{ status = $rawRules.Status; error = $rawRules.Error; items = @($labelItems) }
        adaptiveScopes = [pscustomobject]@{ status = $rawScopes.Status; count = @($rawScopes.Data).Count }
    }
}
