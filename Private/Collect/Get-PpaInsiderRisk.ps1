# Get-PpaInsiderRisk.ps1 - collector for section 04 (Insider Risk Management).
# Attempts Get-InsiderRiskPolicy read-only (may be CommandNotFound or AccessDenied - IRM
# reads need an IRM role group beyond Compliance Reader). Projects to client-safe metadata:
# policy NAME, scenario (template identifier), workloads, created date.
# VERIFIED (2026-07-02 sandbox): Get-InsiderRiskPolicy returns a tenant-settings pseudo-object
# (Name = IRM_Tenant_Setting_<guid>, InsiderRiskScenario = TenantSetting) that is NOT a policy -
# it is excluded from all counts and inventories, otherwise a tenant with zero real policies
# reports as having one. ASCII-only source. Depends on Invoke-PpaReadCmdlet.ps1.

Set-StrictMode -Off

function Get-PpaInsiderRisk {
    [CmdletBinding()]
    param()

    $raw = Invoke-PpaReadCmdlet -Name 'Get-InsiderRiskPolicy'

    $items = New-Object System.Collections.Generic.List[object]
    if ($raw.Status -eq 'Ok') {
        foreach ($p in @($raw.Data)) {
            $scenario = ''
            if ($p.PSObject.Properties.Name -contains 'InsiderRiskScenario') { $scenario = [string]$p.InsiderRiskScenario }
            # The tenant-settings pseudo-policy is configuration, not a policy (VERIFIED).
            if ($scenario -eq 'TenantSetting') { continue }
            $workloads = ''
            if ($p.PSObject.Properties.Name -contains 'Workload') { $workloads = (@($p.Workload) -join ', ') }
            $created = ''
            foreach ($prop in @('WhenCreatedUTC', 'WhenCreated', 'CreationTimeUtc')) {
                if ($p.PSObject.Properties.Name -contains $prop -and $p.$prop) { $created = ([datetime]$p.$prop).ToString('yyyy-MM-dd'); break }
            }
            $items.Add([pscustomobject]@{
                name      = [string]$p.Name
                scenario  = $scenario
                workloads = $workloads
                created   = $created
            })
        }
    }
    $count = if ($raw.Status -eq 'Ok') { $items.Count } else { $null }

    return [pscustomobject]@{
        policies = [pscustomobject]@{ status = $raw.Status; error = $raw.Error; count = $count; items = $items.ToArray() }
    }
}
