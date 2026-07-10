# Get-PpaRetention.ps1 - collector for section 03 (Retention & Records).
# Reads Get-RetentionCompliancePolicy (scope + locations), Get-RetentionComplianceRule
# (labels + auto-apply condition), Get-AdaptiveScope (count) and Get-ComplianceTag
# (the retention-label friendly-name inventory) - all read-only. Projects to
# client-safe metadata: policy/label NAMES, scope type, location TYPES, and whether an
# auto-apply condition exists (never the condition contents/query).
# ASCII-only source. Depends on Invoke-PpaReadCmdlet.ps1.
#
# Pre-publish Part 7: on a live tenant a label-publishing rule carries an
# auto-GUID .Name; the published label lives in PublishComplianceTag (visible-to-
# users) or ApplyComplianceTag (auto-applied) - and either may ITSELF be a GUID.
# Get-PpaRetentionRuleLabel prefers the tag reference over the rule name and
# resolves it through the Get-ComplianceTag inventory; anything unresolvable
# passes through verbatim (orphan fallback), so hand-authored name-based fixtures
# render exactly as before. NOTE: the auto-apply property linkage remains
# best-effort until confirmed against a live tenant.

Set-StrictMode -Off

function Get-PpaRetentionRuleLabel {
    # Display label for ONE retention rule: prefer the published/applied tag over
    # the (often auto-GUID) rule name, then resolve a GUID-valued reference to the
    # friendly tag name; keep the reference verbatim when unmapped - a deleted or
    # unreadable tag must still show SOMETHING, never vanish.
    param($Rule, $TagMap)
    $ref = if ($Rule.PublishComplianceTag) { [string]$Rule.PublishComplianceTag }
           elseif ($Rule.ApplyComplianceTag) { [string]$Rule.ApplyComplianceTag }
           else { [string]$Rule.Name }
    if ($ref -and $TagMap.ContainsKey($ref)) { return $TagMap[$ref] }
    return $ref
}

function Get-PpaRetention {
    [CmdletBinding()]
    param()

    $rawPols   = Invoke-PpaReadCmdlet -Name 'Get-RetentionCompliancePolicy'
    $rawRules  = Invoke-PpaReadCmdlet -Name 'Get-RetentionComplianceRule'
    $rawScopes = Invoke-PpaReadCmdlet -Name 'Get-AdaptiveScope'
    # Part 7: the friendly-name inventory behind Get-PpaRetentionRuleLabel. Folded
    # into the outcome below like every other read - an unreadable tag list
    # degrades visibility honestly rather than silently showing raw references.
    $rawTags   = Invoke-PpaReadCmdlet -Name 'Get-ComplianceTag'

    # Tag resolution map: Guid, ImmutableId (when present) and Name all key the
    # friendly tag Name. PS hashtable literals compare string keys
    # case-insensitively, which covers GUID casing differences for free.
    $tagMap = @{}
    foreach ($t in @($rawTags.Data)) {
        if ($null -eq $t) { continue }
        foreach ($k in @([string]$t.Guid, [string]$t.ImmutableId, [string]$t.Name)) {
            if (-not [string]::IsNullOrEmpty($k) -and -not $tagMap.ContainsKey($k)) { $tagMap[$k] = [string]$t.Name }
        }
    }

    $policyItems = foreach ($p in @($rawPols.Data)) {
        $locs = New-Object System.Collections.Generic.List[string]
        if (@($p.SharePointLocation).Count   -gt 0) { $locs.Add('SharePoint') }
        if (@($p.ExchangeLocation).Count     -gt 0) { $locs.Add('Exchange') }
        if (@($p.ModernGroupLocation).Count  -gt 0) { $locs.Add('Groups') }
        if (@($p.OneDriveLocation).Count     -gt 0) { $locs.Add('OneDrive') }
        $ruleLabels = @($rawRules.Data | Where-Object { $_.Policy -eq $p.Guid -or $_.ParentPolicyName -eq $p.Name } | ForEach-Object { Get-PpaRetentionRuleLabel -Rule $_ -TagMap $tagMap })
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
        [pscustomobject]@{ name = (Get-PpaRetentionRuleLabel -Rule $r -TagMap $tagMap); guid = Get-PpaOptionalGuid $r; autoApply = [bool]$auto }
    }

    return [pscustomobject]@{
        outcome        = Resolve-PpaCollectorOutcome -ReadStatuses @($rawPols.Status, $rawRules.Status, $rawScopes.Status, $rawTags.Status) -ItemCount (@($policyItems).Count + @($labelItems).Count + @($rawScopes.Data).Count)
        policies       = [pscustomobject]@{ status = $rawPols.Status;  error = $rawPols.Error;  items = @($policyItems) }
        labels         = [pscustomobject]@{ status = $rawRules.Status; error = $rawRules.Error; items = @($labelItems) }
        adaptiveScopes = [pscustomobject]@{ status = $rawScopes.Status; count = @($rawScopes.Data).Count }
    }
}
