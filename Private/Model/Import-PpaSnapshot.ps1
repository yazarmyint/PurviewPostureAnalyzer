# Import-PpaSnapshot.ps1 - the snapshot loader (Wave 4 spec 3.4/3.5).
# Engine-agnostic code: the PS 7 gate lives at the DELTA ENTRY POINT (spec section 1),
# not here, so the round-trip pinned test can exercise the loader under 5.1 too.
# Validates: schemaVersion present, major supported, required top-level fields; then
# coerces every declared array field (schema manifest) so single-element and empty
# arrays behave identically after ConvertFrom-Json. Fails with actionable messages.
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function ConvertTo-PpaArray {
    # Declared-array coercion: null -> @(); scalar -> one-element array; array as-is.
    param($Value)
    if ($null -eq $Value) { return , @() }
    return , @($Value)
}

function Import-PpaSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Snapshot file not found: '$Path'."
    }
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    try { $snap = $text | ConvertFrom-Json }
    catch { throw "Snapshot file is not valid JSON: '$Path'. $($_.Exception.Message)" }

    if ($null -eq $snap -or $snap.PSObject.Properties.Name -notcontains 'schemaVersion' -or $null -eq $snap.schemaVersion) {
        throw "File '$Path' has no schemaVersion - is this a PurviewPostureAnalyzer snapshot? Snapshots are written as PPA-Snapshot_*.json alongside the HTML report."
    }

    $schema   = Get-PpaSnapshotSchema
    $ourMajor = [int]$schema.schemaVersion.major
    $ourMinor = [int]$schema.schemaVersion.minor
    $major    = [int]$snap.schemaVersion.major
    $minor    = [int]$snap.schemaVersion.minor
    if ($major -ne $ourMajor) {
        throw ("Snapshot '{0}' is schema v{1}, this tool compares schema v{2}. Re-run the newer tool against the tenant to produce a comparable snapshot." -f (Split-Path -Leaf $Path), $major, $ourMajor)
    }
    if ($minor -gt $ourMinor) {
        # Tolerant read (ruled 3.5): unknown fields ignored, one summary warning.
        Write-Warning ("Snapshot '{0}' is schema v{1}.{2} - a newer minor than this tool (v{3}.{4}); unknown fields are ignored." -f (Split-Path -Leaf $Path), $major, $minor, $ourMajor, $ourMinor)
    }

    $required = @('snapshotId', 'capturedAt', 'sectionsRun', 'collectorOutcomes', 'objects', 'findings')
    $missing  = @($required | Where-Object { $snap.PSObject.Properties.Name -notcontains $_ })
    if ($missing.Count -gt 0) {
        throw ("Snapshot '{0}' is missing required field(s): {1}. It may be truncated or not a PPA snapshot." -f (Split-Path -Leaf $Path), ($missing -join ', '))
    }

    # ---- declared-array coercion ----
    $snap.sectionsRun = ConvertTo-PpaArray $snap.sectionsRun
    $snap.findings    = ConvertTo-PpaArray $snap.findings
    foreach ($typeProp in @($snap.objects.PSObject.Properties)) {
        $typeName = $typeProp.Name
        $coerced  = ConvertTo-PpaArray $typeProp.Value
        $snap.objects.$typeName = $coerced
        $def = $null
        if ($schema.types.PSObject.Properties.Name -contains $typeName) { $def = $schema.types.$typeName }
        if ($null -eq $def) { continue }   # unknown type from a newer minor: tolerated
        $arrays = @($def.arrays | ForEach-Object { [string]$_ })
        if ($arrays.Count -eq 0) { continue }
        foreach ($item in @($snap.objects.$typeName)) {
            foreach ($arrName in $arrays) {
                if ($item.PSObject.Properties.Name -contains $arrName) {
                    $item.$arrName = ConvertTo-PpaArray $item.$arrName
                }
            }
        }
    }

    return $snap
}
