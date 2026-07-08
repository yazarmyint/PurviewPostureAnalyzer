# New-PpaSnapshot.ps1 - builds the JSON snapshot model (Wave 4 spec 3.2/3.3).
# The snapshot is the versioned, UNREDACTED serialization of normalized collector
# objects + evaluated findings written alongside the HTML report; delta mode diffs
# two of them offline. This file only BUILDS the ordered model; Export-PpaSnapshot
# serializes it (ConvertTo-Json -Depth 16 always) and Import-PpaSnapshot loads it.
#
# ORDERING CONTRACT (golden-file test pins all of this, both engines):
#   - top-level properties in schema order: schemaVersion, toolVersion, snapshotId,
#     capturedAt, tenantId, profile, sectionsRun, redactionState, denylistVersion,
#     environment, collectorOutcomes, objects, findings
#   - collectorOutcomes and objects keys: alphabetical
#   - environment.modules keys: alphabetical
#   - type arrays and findings: stable input order (as collected / as analyzed)
#   - every object: _key, _keySource first, then the projection's own properties
# Identity contract: guid/_key are OPAQUE STRINGS end-to-end (spec 3.3 addendum) -
# no GUID parsing or validation here or anywhere downstream.
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function Get-PpaSnapshotSchema {
    # The reviewed schema manifest: schemaVersion + per-type source/section/declared
    # arrays. Lives next to this file; reviewed like the provenance registry.
    $path = Join-Path $PSScriptRoot 'ppa-snapshot-schema.json'
    return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Get-PpaPostureDenylist {
    # The reviewed compare-time denylist. The writer records only its version string
    # in snapshot metadata (information only - the differ always uses the current list).
    $path = Join-Path $PSScriptRoot 'ppa-posture-denylist.json'
    return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Get-PpaRawPathValue {
    # Walk a dotted path ('policies.items') into a collector output. '' means root.
    param($Root, [string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $Root }
    $cur = $Root
    foreach ($seg in ($Path -split '\.')) {
        if ($null -eq $cur) { return $null }
        $cur = $cur.$seg
    }
    return $cur
}

function New-PpaSnapshotModel {
    [CmdletBinding()]
    param(
        # Hashtable: section id -> collector output (null when the collector crashed).
        [Parameter(Mandatory = $true)] $RawMap,
        # Post-selection section objects (findings source), in report order.
        [Parameter(Mandatory = $true)][AllowEmptyCollection()] $Sections,
        # Run meta; consumed: version (toolVersion), tenantId (may be absent).
        [Parameter(Mandatory = $true)] $Meta,
        [Parameter(Mandatory = $true)][datetime]$CapturedAt,
        [Parameter(Mandatory = $true)][string]$SnapshotId,
        [string]$ProfileName,
        # Sections included in this snapshot, in orchestration order.
        [string[]]$SectionIds = @('Sensitivity_Labels', 'Data_Loss_Prevention', 'Retention', 'Insider_Risk', 'Audit', 'eDiscovery', 'Communication_Compliance', 'DSPM_for_AI'),
        # Injectable for deterministic tests; default captures the live engine.
        $Environment = $null
    )

    $schema    = Get-PpaSnapshotSchema
    $knownIds  = @('Sensitivity_Labels', 'Data_Loss_Prevention', 'Retention', 'Insider_Risk', 'Audit', 'eDiscovery', 'Communication_Compliance', 'DSPM_for_AI')
    $runIds    = @($SectionIds)

    # ---- environment (spec 3.2) ----
    if ($null -eq $Environment) {
        $mods = [ordered]@{}
        foreach ($mName in @('ExchangeOnlineManagement') | Sort-Object) {
            $m = @(Get-Module -Name $mName -ErrorAction SilentlyContinue | Sort-Object Version -Descending)
            if ($m.Count -gt 0) { $mods[$mName] = [string]$m[0].Version }
        }
        $Environment = [ordered]@{
            psEdition = [string]$PSVersionTable.PSEdition
            psVersion = [string]$PSVersionTable.PSVersion
            modules   = $mods
        }
    }

    # ---- collectorOutcomes: every known collector, alphabetical ----
    # Failed = attempted-and-errored (the orchestrator always attempts every
    # collector and hands a $null raw when one crashed); NotRun = never attempted
    # (no RawMap entry at all - reserved for future orchestration paths).
    $outcomes = [ordered]@{}
    foreach ($id in (@($knownIds + $runIds) | Select-Object -Unique | Sort-Object)) {
        if ($runIds -notcontains $id) { $outcomes[$id] = 'Skipped'; continue }
        if (-not $RawMap.ContainsKey($id)) { $outcomes[$id] = 'NotRun'; continue }
        $raw = $RawMap[$id]
        if ($null -eq $raw) { $outcomes[$id] = 'Failed'; continue }
        $o = [string]$raw.outcome
        $outcomes[$id] = $(if ([string]::IsNullOrEmpty($o)) { 'Failed' } else { $o })
    }

    # ---- objects: alphabetical type order; keys stamped per KEY_SOURCES.md ----
    $objects = [ordered]@{}
    foreach ($typeProp in ($schema.types.PSObject.Properties | Sort-Object Name)) {
        $typeName = $typeProp.Name
        $def      = $typeProp.Value
        if ($runIds -notcontains [string]$def.section) { continue }
        $raw = $null
        if ($RawMap.ContainsKey([string]$def.section)) { $raw = $RawMap[[string]$def.section] }

        $stamped = New-Object System.Collections.Generic.List[object]
        # Keys are opaque, case-sensitive strings; count occurrences ordinally.
        $seen = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)

        if ([string]$def.kind -eq 'singleton') {
            $src = Get-PpaRawPathValue -Root $raw -Path ([string]$def.path)
            if ($null -ne $src) {
                $o = [ordered]@{ _key = $typeName; _keySource = 'Name'; name = $typeName }
                $fieldNames = $null
                if ($def.PSObject.Properties.Name -contains 'fields' -and $def.fields) { $fieldNames = @($def.fields | ForEach-Object { [string]$_ }) }
                foreach ($p in $src.PSObject.Properties) {
                    if ($p.Name -in @('items', 'outcome')) { continue }
                    if ($null -ne $fieldNames -and $fieldNames -notcontains $p.Name) { continue }
                    $o[$p.Name] = $p.Value
                }
                $stamped.Add($o)
            }
        }
        else {
            foreach ($item in @((Get-PpaRawPathValue -Root $raw -Path ([string]$def.path)))) {
                if ($null -eq $item) { continue }
                # Keying rule: Guid -> Identity -> Name (no projection carries an
                # Identity property today; the slot is reserved by the spec).
                $key = ''; $keySource = 'Name'
                if ($item.PSObject.Properties.Name -contains 'guid' -and -not [string]::IsNullOrEmpty([string]$item.guid)) {
                    $key = [string]$item.guid; $keySource = 'Guid'
                }
                elseif ($item.PSObject.Properties.Name -contains 'name') {
                    $key = [string]$item.name
                }
                if ($seen.ContainsKey($key)) {
                    $seen[$key] = $seen[$key] + 1
                    $newKey = '{0}#{1}' -f $key, $seen[$key]
                    Write-Warning ("Snapshot: duplicate key '{0}' in type '{1}' - disambiguated as '{2}'." -f $key, $typeName, $newKey)
                    $key = $newKey
                }
                else { $seen[$key] = 1 }

                $o = [ordered]@{ _key = $key; _keySource = $keySource }
                foreach ($p in $item.PSObject.Properties) { $o[$p.Name] = $p.Value }
                $stamped.Add($o)
            }
        }
        $objects[$typeName] = $stamped.ToArray()
    }

    # ---- findings: {checkId,status,severity,section,title}; severity is null in the
    # five-status model (field kept for schema stability / FindingChanged semantics) ----
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($sec in @($Sections)) {
        foreach ($f in @($sec.findings)) {
            $findings.Add([ordered]@{
                checkId  = [string]$f.id
                status   = [string]$f.status
                severity = $null
                section  = [string]$sec.id
                title    = [string]$f.title
            })
        }
    }

    $tenantId = $null
    if ($Meta.PSObject.Properties.Name -contains 'tenantId' -and -not [string]::IsNullOrEmpty([string]$Meta.tenantId)) {
        $tenantId = [string]$Meta.tenantId
    }

    return [ordered]@{
        schemaVersion     = [ordered]@{ major = [int]$schema.schemaVersion.major; minor = [int]$schema.schemaVersion.minor }
        toolVersion       = [string]$Meta.version
        snapshotId        = [string]$SnapshotId
        capturedAt        = $CapturedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        tenantId          = $tenantId
        profile           = $(if ([string]::IsNullOrEmpty($ProfileName)) { $null } else { $ProfileName })
        sectionsRun       = $runIds
        redactionState    = 'none'
        denylistVersion   = [string](Get-PpaPostureDenylist).version
        environment       = $Environment
        collectorOutcomes = $outcomes
        objects           = $objects
        findings          = $findings.ToArray()
    }
}
