# Get-PpaAudit.ps1 - collector for section 05 (Audit).
# Reads Get-AdminAuditLogConfig (UnifiedAuditLogIngestionEnabled) and Get-OrganizationConfig
# (AuditDisabled - the org-level mailbox auditing override, AUD-04) - both read-only
# (Exchange Online). ASCII-only source. Depends on Invoke-PpaReadCmdlet.ps1.

Set-StrictMode -Off

function Get-PpaAudit {
    [CmdletBinding()]
    param()

    $rawAudit = Invoke-PpaReadCmdlet -Name 'Get-AdminAuditLogConfig'
    $rawOrg   = Invoke-PpaReadCmdlet -Name 'Get-OrganizationConfig'

    $enabled = $null
    if ($rawAudit.Status -eq 'Ok' -and @($rawAudit.Data).Count -gt 0) {
        $enabled = [bool]($rawAudit.Data[0].UnifiedAuditLogIngestionEnabled)
    }

    # AUD-04: $null means "not read this session" (failed org read OR the property is
    # absent from the returned object) - distinct from $false, so the analyzer can
    # degrade to Verify manually instead of guessing a boolean.
    $mbxAuditDisabled = $null
    if ($rawOrg.Status -eq 'Ok' -and @($rawOrg.Data).Count -gt 0) {
        $org = $rawOrg.Data[0]
        if ($org.PSObject.Properties.Name -contains 'AuditDisabled' -and $null -ne $org.AuditDisabled) {
            $mbxAuditDisabled = [bool]$org.AuditDisabled
        }
    }

    # Both reads govern the outcome: orgStatus is part of the normalized output, so a
    # failed org read is honestly reported as Partial visibility.
    return [pscustomobject]@{
        outcome                 = Resolve-PpaCollectorOutcome -ReadStatuses @($rawAudit.Status, $rawOrg.Status) -ItemCount (@($rawAudit.Data).Count)
        status                  = $rawAudit.Status
        error                   = $rawAudit.Error
        unifiedAuditEnabled     = $enabled
        orgStatus               = $rawOrg.Status
        mailboxAuditingDisabled = $mbxAuditDisabled
    }
}
