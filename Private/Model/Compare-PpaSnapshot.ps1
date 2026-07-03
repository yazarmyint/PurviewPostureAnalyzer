# Compare-PpaSnapshot.ps1 - the delta differ (Wave 4 spec 4.2-4.4). Fully offline:
# consumes two LOADED snapshots (Import-PpaSnapshot), produces the delta model the
# renderer draws. No tenant reads anywhere in delta mode.
#
# Identity contract (spec 3.3/4.3 addenda): _key and guid are OPAQUE STRINGS.
# The rename-reconciliation pass is NON-EMPTY ORDINAL STRING EQUALITY on guid -
# no GUID format parsing or validation. Fixture slug guids are first-class inputs.
#
# NOTE: this file must PARSE under Windows PowerShell 5.1 (the module loader
# dot-sources everything on both engines); delta only EXECUTES on 7+ via the
# Test-PpaDeltaEngine gate at the entry point. No PS7-only syntax here.
# ASCII-only source.

Set-StrictMode -Off

function Test-PpaDeltaEngine {
    # The injectable engine gate (spec section 1): the delta entry point refuses to
    # run below PS 7. Tests redefine this function to exercise the refusal without
    # a real 5.1 host.
    return ($PSVersionTable.PSVersion.Major -ge 7)
}

function Get-PpaSignificantPropertyMap {
    $path = Join-Path $PSScriptRoot 'ppa-significant-properties.json'
    return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Test-PpaDeltaLeaf {
    param($Value)
    if ($null -eq $Value) { return $true }
    if ($Value -is [string] -or $Value -is [System.ValueType]) { return $true }
    return $false
}

function Test-PpaDeltaValueEqual {
    # Strict structural equality for property values. Strings compare ordinal
    # case-sensitive; nested objects compare by property set + values; nested
    # (non-declared) arrays compare order-sensitively. The absent == '' rule is
    # applied by the CALLER at the top property level only.
    param($X, $Y)
    $xl = Test-PpaDeltaLeaf $X; $yl = Test-PpaDeltaLeaf $Y
    if ($xl -ne $yl) { return $false }
    if ($xl) {
        if ($null -eq $X -and $null -eq $Y) { return $true }
        if ($null -eq $X -or $null -eq $Y) { return $false }
        if ($X -is [string] -or $Y -is [string]) { return ([string]$X -ceq [string]$Y) }
        return ($X -eq $Y)
    }
    $xArr = ($X -isnot [System.Management.Automation.PSCustomObject])
    $yArr = ($Y -isnot [System.Management.Automation.PSCustomObject])
    if ($xArr -ne $yArr) { return $false }
    if ($xArr) {
        $xa = @($X); $ya = @($Y)
        if ($xa.Count -ne $ya.Count) { return $false }
        for ($i = 0; $i -lt $xa.Count; $i++) {
            if (-not (Test-PpaDeltaValueEqual $xa[$i] $ya[$i])) { return $false }
        }
        return $true
    }
    $xn = @($X.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object
    $yn = @($Y.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object
    if (($xn -join '|') -cne ($yn -join '|')) { return $false }
    foreach ($n in $xn) {
        if (-not (Test-PpaDeltaValueEqual $X.$n $Y.$n)) { return $false }
    }
    return $true
}

function Get-PpaDeltaArrayCanon {
    # Order-insensitive canonical form for DECLARED array properties: each element
    # becomes a canonical string, the list is sorted, then joined. Two arrays with
    # the same members in any order canonicalize identically.
    param($Value)
    $sep = [string][char]31
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($e in @($Value)) {
        if ($null -eq $e) { $parts.Add('~null') }
        elseif (Test-PpaDeltaLeaf $e) { $parts.Add('s:' + [string]$e) }
        else { $parts.Add('j:' + (ConvertTo-Json -InputObject $e -Compress -Depth 8)) }
    }
    return (@($parts | Sort-Object) -join $sep)
}

function ConvertTo-PpaDeltaDisplay {
    # Human-readable rendering of a property value in a change record.
    param($Value)
    if ($null -eq $Value) { return '' }
    if (Test-PpaDeltaLeaf $Value) { return [string]$Value }
    if ($Value -isnot [System.Management.Automation.PSCustomObject]) {
        $items = @($Value | ForEach-Object { ConvertTo-PpaDeltaDisplay $_ })
        return ('[' + ($items -join ', ') + ']')
    }
    return (ConvertTo-Json -InputObject $Value -Compress -Depth 8)
}

function Compare-PpaSnapshotObject {
    # Property-level compare of one matched object pair. Returns change records.
    # Skips identity metadata (_key/_keySource) and denylisted properties; treats
    # absent property == empty string (A.5 carry-forward); declared arrays compare
    # order-insensitively.
    param($FromObj, $ToObj, [string[]]$DeclaredArrays, [string[]]$Denylist, [string[]]$Significant)
    $changes = New-Object System.Collections.Generic.List[object]
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($p in $FromObj.PSObject.Properties) { if ($names -notcontains $p.Name) { $names.Add($p.Name) } }
    foreach ($p in $ToObj.PSObject.Properties)   { if ($names -notcontains $p.Name) { $names.Add($p.Name) } }
    foreach ($n in $names) {
        if ($n -eq '_key' -or $n -eq '_keySource') { continue }
        if ($Denylist -contains $n) { continue }
        $fv = $null; $tv = $null
        $fHas = ($FromObj.PSObject.Properties.Name -contains $n)
        $tHas = ($ToObj.PSObject.Properties.Name -contains $n)
        if ($fHas) { $fv = $FromObj.$n }
        if ($tHas) { $tv = $ToObj.$n }
        # absent == '' (and null == '') at the top property level: MinValue/all-zeros
        # placeholders normalize to '' upstream, so absent-vs-'' is never a change.
        if (-not $fHas -or $null -eq $fv) { $fv = '' }
        if (-not $tHas -or $null -eq $tv) { $tv = '' }
        $equal = $false
        if ($DeclaredArrays -contains $n) {
            $equal = ((Get-PpaDeltaArrayCanon $fv) -ceq (Get-PpaDeltaArrayCanon $tv))
        }
        else {
            if (($fv -is [string]) -and ($tv -isnot [string]) -and (Test-PpaDeltaLeaf $tv) -and $fv -eq '') {
                # '' vs non-string leaf: real difference; fall through to strict compare
            }
            $equal = Test-PpaDeltaValueEqual $fv $tv
        }
        if (-not $equal) {
            $changes.Add([pscustomobject][ordered]@{
                property    = $n
                from        = ConvertTo-PpaDeltaDisplay $fv
                to          = ConvertTo-PpaDeltaDisplay $tv
                significant = [bool]($Significant -contains $n)
            })
        }
    }
    return $changes.ToArray()
}

function Compare-PpaSnapshotPair {
    # Two loaded snapshots -> the delta model (spec 4.2-4.4). Throws on tenant
    # mismatch (unless -AllowTenantMismatch); warns on absent tenantId and on
    # reversed capturedAt (never auto-swaps).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $From,
        [Parameter(Mandatory = $true)] $To,
        [switch]$AllowTenantMismatch
    )

    $schema   = Get-PpaSnapshotSchema
    $denyFile = Get-PpaPostureDenylist
    $sigMap   = Get-PpaSignificantPropertyMap
    $globalDeny = @($denyFile.global | ForEach-Object { [string]$_ })

    # ---- pre-compare validation (4.2) ----
    $fromTenant = [string]$From.tenantId
    $toTenant   = [string]$To.tenantId
    if ([string]::IsNullOrEmpty($fromTenant) -or [string]::IsNullOrEmpty($toTenant)) {
        Write-Warning 'A snapshot has no tenantId recorded; proceeding without the same-tenant check.'
    }
    elseif ($fromTenant -cne $toTenant) {
        if (-not $AllowTenantMismatch) {
            throw ("Snapshots are from different tenants ('{0}' vs '{1}'). Re-check the inputs, or pass -AllowTenantMismatch to compare anyway." -f $fromTenant, $toTenant)
        }
        Write-Warning ("Comparing snapshots from DIFFERENT tenants ('{0}' vs '{1}') because -AllowTenantMismatch was passed." -f $fromTenant, $toTenant)
    }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $styles  = [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $fromDt  = [datetime]::Parse([string]$From.capturedAt, $culture, $styles)
    $toDt    = [datetime]::Parse([string]$To.capturedAt, $culture, $styles)
    $spanDays = [int][math]::Round(($toDt - $fromDt).TotalDays)
    if ($fromDt -gt $toDt) {
        Write-Warning ("-DeltaFrom ({0}) is newer than -DeltaTo ({1}); comparing as given - the report reads right to left. Not auto-swapping." -f $From.capturedAt, $To.capturedAt)
    }

    $denylistNote = $null
    if ([string]$From.denylistVersion -cne [string]$To.denylistVersion) {
        $denylistNote = ("Informational: the snapshots recorded denylist versions '{0}' and '{1}'; this comparison used the current tool's list (v{2})." -f $From.denylistVersion, $To.denylistVersion, $denyFile.version)
    }

    $readable = @('Populated', 'Empty')
    $fromRun  = @($From.sectionsRun | ForEach-Object { [string]$_ })
    $toRun    = @($To.sectionsRun | ForEach-Object { [string]$_ })
    $allIds   = New-Object System.Collections.Generic.List[string]
    foreach ($id in $fromRun) { if ($allIds -notcontains $id) { $allIds.Add($id) } }
    foreach ($id in $toRun)   { if ($allIds -notcontains $id) { $allIds.Add($id) } }

    $typeDefs = @($schema.types.PSObject.Properties | Sort-Object Name)

    $sections = New-Object System.Collections.Generic.List[object]
    foreach ($id in $allIds) {
        $inFrom = ($fromRun -contains $id)
        $inTo   = ($toRun -contains $id)

        $rec = [ordered]@{
            id = $id; state = ''; reason = ''
            fromOutcome = [string]$From.collectorOutcomes.$id
            toOutcome   = [string]$To.collectorOutcomes.$id
            visibilityNote = ''
            added = @(); removed = @(); modified = @()
            findingChanges = @(); unchangedCount = 0
            identityWarning = $false
        }

        # 4.3: compared iff present in BOTH sectionsRun - NEVER mass Added/Removed.
        if (-not ($inFrom -and $inTo)) {
            $rec.state = 'NotCompared'
            $side = ''
            if (-not $inFrom) { $side = 'snapshot A (-DeltaFrom)' } else { $side = 'snapshot B (-DeltaTo)' }
            $rec.reason = ("section {0} was not run in {1}, so it cannot be compared." -f $id, $side)
            $sections.Add([pscustomobject]$rec)
            continue
        }

        $sectionTypes = @($typeDefs | Where-Object { [string]$_.Value.section -eq $id })

        # Visibility precedence: either side degraded -> suppress object-level diff.
        $fo = $rec.fromOutcome; $to2 = $rec.toOutcome
        if (($readable -notcontains $fo) -or ($readable -notcontains $to2)) {
            $rec.state = 'VisibilityChanged'
            if (($readable -contains $to2) -and ($readable -notcontains $fo)) {
                $n = 0
                foreach ($t in $sectionTypes) {
                    if ($To.objects.PSObject.Properties.Name -contains $t.Name) { $n += @($To.objects.$($t.Name)).Count }
                }
                $rec.visibilityNote = ("{0} -> {1}: {2} object(s) now observable." -f $fo, $to2, $n)
            }
            elseif (($readable -contains $fo) -and ($readable -notcontains $to2)) {
                $rec.visibilityNote = ("{0} -> {1}: object-level comparison suppressed until visibility returns." -f $fo, $to2)
            }
            else {
                $rec.visibilityNote = ("{0} -> {1}: visibility degraded on both sides; nothing object-level can be asserted." -f $fo, $to2)
            }
        }
        else {
            $rec.state = 'Compared'
            $added    = New-Object System.Collections.Generic.List[object]
            $removed  = New-Object System.Collections.Generic.List[object]
            $modified = New-Object System.Collections.Generic.List[object]
            $unchanged = 0

            foreach ($t in $sectionTypes) {
                $typeName = $t.Name
                $declared = @($t.Value.arrays | ForEach-Object { [string]$_ })
                $deny = @($globalDeny)
                if ($denyFile.perType.PSObject.Properties.Name -contains $typeName) {
                    $deny += @($denyFile.perType.$typeName | ForEach-Object { [string]$_ })
                }
                $sig = @()
                if ($sigMap.PSObject.Properties.Name -contains $typeName) {
                    $sig = @($sigMap.$typeName | ForEach-Object { [string]$_ })
                }

                $fromArr = @(); $toArr = @()
                if ($From.objects.PSObject.Properties.Name -contains $typeName) { $fromArr = @($From.objects.$typeName) }
                if ($To.objects.PSObject.Properties.Name -contains $typeName)   { $toArr = @($To.objects.$typeName) }

                $fromMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
                foreach ($o in $fromArr) { $fromMap[[string]$o._key] = $o }
                $toMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
                foreach ($o in $toArr) { $toMap[[string]$o._key] = $o }

                $removedCand = New-Object System.Collections.Generic.List[object]
                $addedCand   = New-Object System.Collections.Generic.List[object]

                foreach ($k in $fromMap.Keys) {
                    if ($toMap.ContainsKey($k)) {
                        $fObj = $fromMap[$k]; $tObj = $toMap[$k]
                        $changes = @(Compare-PpaSnapshotObject -FromObj $fObj -ToObj $tObj -DeclaredArrays $declared -Denylist $deny -Significant $sig)
                        if ($changes.Count -eq 0) { $unchanged++ }
                        else {
                            $m = [ordered]@{
                                type = $typeName; key = $k; name = [string]$tObj.name
                                renamed = $false; renameFrom = ''; renameTo = ''
                                changes = $changes
                            }
                            $nameChange = @($changes | Where-Object { $_.property -eq 'name' })
                            if ($nameChange.Count -gt 0) {
                                $m.renamed = $true; $m.renameFrom = [string]$fObj.name; $m.renameTo = [string]$tObj.name
                            }
                            $modified.Add([pscustomobject]$m)
                        }
                    }
                    else { $removedCand.Add($fromMap[$k]) }
                }
                foreach ($k in $toMap.Keys) {
                    if (-not $fromMap.ContainsKey($k)) { $addedCand.Add($toMap[$k]) }
                }

                # GUID-equality reconciliation (spec 4.3 + A.5 addendum): pair
                # key-divergent objects by NON-EMPTY ordinal string equality on guid,
                # so renames never appear as Removed+Added.
                $addedByGuid = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
                foreach ($o in $addedCand) {
                    $g = [string]$o.guid
                    if (-not [string]::IsNullOrEmpty($g) -and -not $addedByGuid.ContainsKey($g)) { $addedByGuid[$g] = $o }
                }
                $stillRemoved = New-Object System.Collections.Generic.List[object]
                foreach ($o in $removedCand) {
                    $g = [string]$o.guid
                    if (-not [string]::IsNullOrEmpty($g) -and $addedByGuid.ContainsKey($g)) {
                        $pair = $addedByGuid[$g]
                        [void]$addedByGuid.Remove($g)
                        $addedCand.Remove($pair) | Out-Null
                        $changes = @(Compare-PpaSnapshotObject -FromObj $o -ToObj $pair -DeclaredArrays $declared -Denylist $deny -Significant $sig)
                        $modified.Add([pscustomobject][ordered]@{
                            type = $typeName; key = [string]$pair._key; name = [string]$pair.name
                            renamed = $true; renameFrom = [string]$o.name; renameTo = [string]$pair.name
                            changes = $changes
                        })
                    }
                    else { $stillRemoved.Add($o) }
                }

                foreach ($o in $stillRemoved) { $removed.Add([pscustomobject]@{ type = $typeName; key = [string]$o._key; name = [string]$o.name }) }
                foreach ($o in $addedCand)    { $added.Add([pscustomobject]@{ type = $typeName; key = [string]$o._key; name = [string]$o.name }) }
            }

            $rec.added = $added.ToArray()
            $rec.removed = $removed.ToArray()
            $rec.modified = $modified.ToArray()
            $rec.unchangedCount = $unchanged
            # Identity-failure heuristic (4.4): everything moved, nothing matched.
            $rec.identityWarning = (($added.Count -gt 0) -and ($removed.Count -gt 0) -and ($modified.Count -eq 0) -and ($unchanged -eq 0))
        }

        # FindingChanged: compared for every section run on both sides (only the
        # OBJECT-level diff is visibility-suppressed). Severity is reserved: while
        # null on both sides it is ignored entirely and never rendered.
        $fFind = @($From.findings | Where-Object { [string]$_.section -eq $id })
        $tFind = @($To.findings | Where-Object { [string]$_.section -eq $id })
        $fc = New-Object System.Collections.Generic.List[object]
        foreach ($ff in $fFind) {
            $tf = @($tFind | Where-Object { [string]$_.checkId -eq [string]$ff.checkId })
            if ($tf.Count -eq 0) { continue }
            $tf = $tf[0]
            $statusChanged = ([string]$ff.status -cne [string]$tf.status)
            $sevChanged = $false
            if ($null -ne $ff.severity -or $null -ne $tf.severity) {
                $sevChanged = ([string]$ff.severity -cne [string]$tf.severity)
            }
            if ($statusChanged -or $sevChanged) {
                $r = [ordered]@{
                    checkId = [string]$ff.checkId; title = [string]$tf.title
                    fromStatus = [string]$ff.status; toStatus = [string]$tf.status
                }
                if ($sevChanged) { $r.fromSeverity = [string]$ff.severity; $r.toSeverity = [string]$tf.severity }
                $fc.Add([pscustomobject]$r)
            }
        }
        $rec.findingChanges = $fc.ToArray()

        $sections.Add([pscustomobject]$rec)
    }

    return [pscustomobject][ordered]@{
        from = [pscustomobject][ordered]@{
            snapshotId = [string]$From.snapshotId; capturedAt = [string]$From.capturedAt
            tenantId = $From.tenantId; toolVersion = [string]$From.toolVersion
            denylistVersion = [string]$From.denylistVersion
        }
        to = [pscustomobject][ordered]@{
            snapshotId = [string]$To.snapshotId; capturedAt = [string]$To.capturedAt
            tenantId = $To.tenantId; toolVersion = [string]$To.toolVersion
            denylistVersion = [string]$To.denylistVersion
        }
        spanDays = $spanDays
        denylistNote = $denylistNote
        sections = $sections.ToArray()
    }
}
