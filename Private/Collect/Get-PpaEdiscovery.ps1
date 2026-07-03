# Get-PpaEdiscovery.ps1 - collector for section 06 (eDiscovery).
# Reads Get-ComplianceCase (Name, Status) - read-only. Projects case NAMES + status only.
# ASCII-only source. Depends on Invoke-PpaReadCmdlet.ps1.

Set-StrictMode -Off

function Get-PpaEdiscovery {
    [CmdletBinding()]
    param()

    $raw = Invoke-PpaReadCmdlet -Name 'Get-ComplianceCase'
    $cases = foreach ($c in @($raw.Data)) {
        [pscustomobject]@{ name = [string]$c.Name; caseStatus = [string]$c.Status }
    }

    return [pscustomobject]@{
        outcome = Resolve-PpaCollectorOutcome -ReadStatuses @($raw.Status) -ItemCount (@($cases).Count)
        cases   = [pscustomobject]@{ status = $raw.Status; error = $raw.Error; items = @($cases) }
    }
}
