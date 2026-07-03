# Export-PpaSnapshot.ps1 - serializes and writes the snapshot model (Wave 4 spec 3.1).
# Serialization rule (spec section 1, pinned): ConvertTo-Json -InputObject ... -Depth 16
# ALWAYS - PS 5.1 truncates silently past -Depth, and the torture fixture's depth
# canary proves 16 is sufficient. Snapshots are ALWAYS UNREDACTED in v1 (ruled): they
# carry UPNs and scope identities and are engagement-confidential; the redacted HTML
# report is the artifact that travels. A one-line console notice says so on every write.
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function Get-PpaTenantIdShort {
    # Filename token: lowercase alphanumerics of tenantId, first 8 chars; 'unknown'
    # when the snapshot has no tenant identity.
    param([string]$TenantId)
    $s = ([string]$TenantId).ToLowerInvariant() -replace '[^a-z0-9]', ''
    if ($s.Length -eq 0) { return 'unknown' }
    if ($s.Length -gt 8) { return $s.Substring(0, 8) }
    return $s
}

function Export-PpaSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Model,
        [Parameter(Mandatory = $true)][string]$Directory,
        # Raw collector outputs (section id -> output); only written with -IncludeRawCapture.
        $RawMap = $null,
        [switch]$IncludeRawCapture
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    # PPA-Snapshot_<tenantIdShort>_<capturedAtCompact>Z_<snapshotId8>.json
    # capturedAt is already ISO-8601 UTC ('2026-07-03T14:15:00Z'); stripping '-' and
    # ':' yields the compact form including the trailing Z. snapshotId8 = first 8
    # chars of the GUID string (opaque - no parsing).
    $short   = Get-PpaTenantIdShort ([string]$Model.tenantId)
    $compact = ([string]$Model.capturedAt) -replace '-', '' -replace ':', ''
    $id8     = ([string]$Model.snapshotId).Substring(0, [Math]::Min(8, ([string]$Model.snapshotId).Length))
    $suffix  = '{0}_{1}_{2}.json' -f $short, $compact, $id8

    $snapshotPath = Join-Path $Directory ('PPA-Snapshot_' + $suffix)
    $json = ConvertTo-Json -InputObject $Model -Depth 16
    [System.IO.File]::WriteAllText($snapshotPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("Snapshot : {0} (UNREDACTED - contains UPNs and scope identities; engagement-confidential. The redacted HTML report is the artifact that travels.)" -f $snapshotPath)

    $rawPath = $null
    if ($IncludeRawCapture) {
        # Debug artifact OUTSIDE the schema - never referenced by delta (ruled 3.1).
        $rawPath = Join-Path $Directory ('PPA-RawCapture_' + $suffix)
        $rawOrdered = [ordered]@{}
        foreach ($k in @($RawMap.Keys | Sort-Object)) { $rawOrdered[[string]$k] = $RawMap[$k] }
        [System.IO.File]::WriteAllText($rawPath, (ConvertTo-Json -InputObject $rawOrdered -Depth 16), (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ("RawCapture: {0} (debug only - outside the snapshot schema)" -f $rawPath)
    }

    return [pscustomobject]@{ SnapshotPath = $snapshotPath; RawCapturePath = $rawPath }
}
