# Export-PpaJson.ps1 - the secondary export. Serializes the SAME normalized object the
# HTML renderer consumes (report-first: JSON is a byproduct, not the design center).
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function Export-PpaJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Normalized,
        [Parameter(Mandatory = $true)] [string]$Path,
        [int]$Depth = 12
    )
    $json = $Normalized | ConvertTo-Json -Depth $Depth
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $Path
}
