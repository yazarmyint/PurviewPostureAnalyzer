# Get-PpaRemediationCatalog.ps1 - loads the static remediation-snippet map
# (Data/remediation-catalog.json), keyed by check ID. Display-only content: the
# renderer shows portalPath / cmdlet / learnUrl inside Improvement and Recommendation
# finding cards; nothing here is ever executed (read-only guarantee unchanged).
# Every drafted snippet is a DRAFT until reviewed - see docs/REMEDIATION_REVIEW.md.
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function Get-PpaRemediationCatalog {
    param([string]$Path)
    if (-not $Path) {
        $Path = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Data\remediation-catalog.json'
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Get-PpaRemediation {
    # The remediation block for one check id, or $null when the catalog has no entry.
    param($Catalog, [Parameter(Mandatory = $true)][string]$CheckId)
    if ($null -eq $Catalog -or $null -eq $Catalog.checks) { return $null }
    if ($Catalog.checks.PSObject.Properties.Name -contains $CheckId) { return $Catalog.checks.$CheckId }
    return $null
}
