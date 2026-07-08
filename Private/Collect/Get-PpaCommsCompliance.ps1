# Get-PpaCommsCompliance.ps1 - collector for section 07 (Communication Compliance).
# Reads Get-SupervisoryReviewPolicyV2 (count) - read-only, confirmed on Microsoft Learn.
# The E5 license gate is passed to the analyzer separately.
# ASCII-only source. Depends on Invoke-PpaReadCmdlet.ps1.

Set-StrictMode -Off

function Get-PpaCommsCompliance {
    [CmdletBinding()]
    param()

    $raw = Invoke-PpaReadCmdlet -Name 'Get-SupervisoryReviewPolicyV2'
    $count = if ($raw.Status -eq 'Ok') { @($raw.Data).Count } else { $null }

    return [pscustomobject]@{
        outcome  = Resolve-PpaCollectorOutcome -ReadStatuses @($raw.Status) -ItemCount (@($raw.Data).Count)
        policies = [pscustomobject]@{ status = $raw.Status; error = $raw.Error; count = $count }
    }
}
