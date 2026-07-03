# Get-PpaLicenseRequirements.ps1 - loads the static license-annotation map
# (Data/license-requirements.json). This is ANNOTATION, not detection: the map records
# which tier each check's feature requires per the Microsoft Purview service description
# (see the map's source + lastReviewed fields). The tool never reads the tenant's
# subscriptions. ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function Get-PpaLicenseRequirements {
    param([string]$Path)
    if (-not $Path) {
        $Path = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Data\license-requirements.json'
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Get-PpaRequirement {
    # The 'Requires' annotation string for one check id, or $null when the map has no
    # entry (E3-baseline features are deliberately unannotated).
    param($Map, [Parameter(Mandatory = $true)][string]$CheckId)
    if ($null -eq $Map -or $null -eq $Map.checks) { return $null }
    if ($Map.checks.PSObject.Properties.Name -contains $CheckId) { return [string]$Map.checks.$CheckId.requires }
    return $null
}
