# Invoke-PpaDelta.ps1 - the delta-mode entry (Wave 4 spec 4.1). Fully offline:
# file-in, HTML-out; no tenant session is created or required. PS 7+ only - the
# FIRST action is the injectable engine gate (spec section 1), so nothing else in
# delta ever executes on Windows PowerShell 5.1.
# ASCII-only source (parses under 5.1; executes under 7+).

Set-StrictMode -Off

function Invoke-PpaDelta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FromPath,
        [Parameter(Mandatory = $true)][string]$ToPath,
        [string]$OutputPath,
        [switch]$Redact,
        [switch]$RedactNames,
        [switch]$AllowTenantMismatch
    )

    if (-not (Test-PpaDeltaEngine)) {
        throw 'Delta mode requires PowerShell 7 or later (run under pwsh). Snapshot capture works on Windows PowerShell 5.1; comparing snapshots does not.'
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = 'Outputs' }
    if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path -Path (Get-Location).Path -ChildPath $OutputPath
    }
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $from = Import-PpaSnapshot -Path $FromPath
    $to   = Import-PpaSnapshot -Path $ToPath
    $delta = Compare-PpaSnapshotPair -From $from -To $to -AllowTenantMismatch:$AllowTenantMismatch

    $html = Export-PpaDeltaReport -Delta $delta -Redact:$Redact -RedactNames:$RedactNames

    $short = Get-PpaTenantIdShort ([string]$from.tenantId)
    $fromCompact = ([string]$from.capturedAt) -replace '-', '' -replace ':', ''
    $toCompact   = ([string]$to.capturedAt) -replace '-', '' -replace ':', ''
    $deltaPath = Join-Path $OutputPath ('PPA-Delta_{0}_{1}_{2}.html' -f $short, $fromCompact, $toCompact)
    [System.IO.File]::WriteAllText($deltaPath, $html, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Delta report : $deltaPath"

    return [pscustomobject]@{ DeltaPath = $deltaPath; Delta = $delta }
}
