# Get-PpaRunContext.ps1 - builds the report header (meta) for a run: date, organization,
# tenant, operator, mode. Best-effort and read-only - every lookup goes through the
# read-only wrapper and falls back to a safe placeholder. ASCII-only source.

Set-StrictMode -Off

function Get-PpaRunContext {
    [CmdletBinding()]
    param(
        [string]$Organization,
        [datetime]$AsOf = (Get-Date)
    )

    $mid = Get-PpaMidDot
    $now = $AsOf.ToUniversalTime()

    $tenant   = 'Not detected'
    $operator = 'Not detected'

    # Tenant from the default accepted domain (Exchange Online). No Graph (decision D9).
    $dom = Invoke-PpaReadCmdlet -Name 'Get-AcceptedDomain'
    if ($dom.Status -eq 'Ok') {
        $default = @($dom.Data | Where-Object { $_.Default -eq $true })
        if ($default.Count -gt 0 -and $default[0].DomainName) { $tenant = [string]$default[0].DomainName }
    }

    # Operator from the Exchange Online / S&C connection.
    $conn = Invoke-PpaReadCmdlet -Name 'Get-ConnectionInformation'
    if ($conn.Status -eq 'Ok' -and @($conn.Data).Count -gt 0 -and $conn.Data[0].UserPrincipalName) {
        $operator = [string]$conn.Data[0].UserPrincipalName
    }

    $org = if ($Organization) { $Organization } else { $tenant }

    return [pscustomobject]@{
        reportTitle = 'Configuration Analyzer for Microsoft Purview'
        version     = '2.0'
        versionDate = 'June 2026'
        dateDisplay = ($now.ToString('dd-MMM-yyyy HH:mm') + ' UTC')
        organization = $org
        tenant      = $tenant
        operator    = $operator
        mode        = "Read-only $mid configuration metadata only"
    }
}
