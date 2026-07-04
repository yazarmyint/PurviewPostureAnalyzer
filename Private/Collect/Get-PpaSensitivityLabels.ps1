# Get-PpaSensitivityLabels.ps1 - collector for section 01 (Sensitivity Labels).
# Reads Get-Label, Get-LabelPolicy, Get-AutoSensitivityLabelPolicy (all read-only) and
# projects each to a client-safe metadata shape: names, priorities, scopes, modes, SIT
# NAMES only - never document content or matched values (PLAN.md guardrails).
# ASCII-only source (Windows PowerShell 5.1). Depends on Invoke-PpaReadCmdlet.ps1.
#
# Container coverage (LABELS-04 "0 of 143 labeled") has no single read-only cmdlet; the
# collector marks it NotCollected and the analyzer degrades. A future phase can populate
# it from Graph groups + SPO site inventory.

Set-StrictMode -Off

function ConvertTo-PpaScopeTokens {
    # Normalize a Get-Label ContentType value (comma string, array, or flags) to tokens.
    param($ContentType)
    if ($null -eq $ContentType) { return @() }
    if ($ContentType -is [array]) { return @($ContentType | ForEach-Object { [string]$_ }) }
    return @(([string]$ContentType) -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-PpaSensitivityLabels {
    [CmdletBinding()]
    param()

    $rawLabels = Invoke-PpaReadCmdlet -Name 'Get-Label'
    $rawPols   = Invoke-PpaReadCmdlet -Name 'Get-LabelPolicy'
    $rawAuto   = Invoke-PpaReadCmdlet -Name 'Get-AutoSensitivityLabelPolicy'

    $labelItems = foreach ($l in @($rawLabels.Data)) {
        $displayName = if ($l.DisplayName) { [string]$l.DisplayName } else { [string]$l.Name }
        [pscustomobject]@{
            name     = $displayName
            guid     = [string]$l.Guid
            priority = [int]($l.Priority)
            scopes   = @(ConvertTo-PpaScopeTokens $l.ContentType)
            parentId = [string]$l.ParentId
        }
    }

    $policyItems = foreach ($p in @($rawPols.Data)) {
        # "Assigned To" from the location properties CHECK_CATALOG documents for LABELS-02
        # (ExchangeLocation / ModernGroupLocation). 'All' means published to all users.
        # Real Get-LabelPolicy has no ScopeSummary; an empty scope renders as a dash.
        $locs = @()
        $locs += @($p.ExchangeLocation | ForEach-Object { [string]$_ })
        $locs += @($p.ModernGroupLocation | ForEach-Object { [string]$_ })
        $locs = @($locs | Where-Object { $_ } | Select-Object -Unique)
        $scope = if ($locs -contains 'All') { 'All users' } elseif ($locs.Count -gt 0) { ($locs -join ', ') } else { '' }
        [pscustomobject]@{
            name    = [string]$p.Name
            guid    = Get-PpaOptionalGuid $p
            labels  = @($p.Labels | ForEach-Object { [string]$_ })
            enabled = [bool]($p.Enabled -ne $false)
            scope   = $scope
        }
    }

    $autoItems = foreach ($a in @($rawAuto.Data)) {
        [pscustomobject]@{
            name                = [string]$a.Name
            guid                = Get-PpaOptionalGuid $a
            mode                = [string]$a.Mode
            # Part D matrix grounding (documented-only shape): auto-labeling
            # supports Exchange/SharePoint/OneDrive locations only.
            locationScope       = [pscustomobject]@{
                exchange   = (Get-PpaLocationScopeToken $a.ExchangeLocation)
                sharePoint = (Get-PpaLocationScopeToken $a.SharePointLocation)
                oneDrive   = (Get-PpaLocationScopeToken $a.OneDriveLocation)
            }
            locationExceptions  = [pscustomobject]@{
                exchange   = (Test-PpaLocationException $a.ExchangeLocationException)
                sharePoint = (Test-PpaLocationException $a.SharePointLocationException)
                oneDrive   = (Test-PpaLocationException $a.OneDriveLocationException)
            }
            sits                = @($a.SensitiveInformationTypeNames | ForEach-Object { [string]$_ })
            simulationStartDate = ConvertTo-PpaIso8601 $a.SimulationStartDate
            simulationItemCount = [int]($a.SimulationItemCount)
        }
    }

    # Outcome from the three real reads only - the containers block is NotCollected
    # by design (no read-only cmdlet exists) and must not degrade the outcome.
    return [pscustomobject]@{
        outcome    = Resolve-PpaCollectorOutcome -ReadStatuses @($rawLabels.Status, $rawPols.Status, $rawAuto.Status) -ItemCount (@($labelItems).Count + @($policyItems).Count + @($autoItems).Count)
        labels     = [pscustomobject]@{ status = $rawLabels.Status; error = $rawLabels.Error; items = @($labelItems) }
        policies   = [pscustomobject]@{ status = $rawPols.Status;   error = $rawPols.Error;   items = @($policyItems) }
        autoLabels = [pscustomobject]@{ status = $rawAuto.Status;   error = $rawAuto.Error;   items = @($autoItems) }
        containers = [pscustomobject]@{ status = 'NotCollected';    groups = $null;           sites = $null }
    }
}
