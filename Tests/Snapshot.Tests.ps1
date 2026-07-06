# Snapshot.Tests.ps1 - Wave 4 Part B pins: snapshot schema golden file, round-trip
# deep-compare (incl. torture fixture with hostile strings and depth canary), key
# stamping per docs/KEY_SOURCES.md, duplicate-key disambiguation, loader validation,
# file emission (name pattern, unredacted notice, -IncludeRawCapture, -NoSnapshot is
# pinned in Module.Tests). All writer-side: must pass under PS 5.1 AND 7+.
# Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    # The snapshot surface spans Model + Collect + Analyze + Core; glob the whole
    # Private tree like the module loader so new helpers are always in scope.
    foreach ($f in (Get-ChildItem -Path (Join-Path $script:RepoRoot 'Private') -Recurse -Filter '*.ps1')) { . $f.FullName }

    function Read-PpaFixtureJson([string]$RelPath) {
        [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot $RelPath), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }

    # ---- deterministic golden inputs -------------------------------------------------
    # Everything the model depends on is injected, so the same bytes come out of the
    # writer on every run (engine JSON formatting aside - see the golden Describes).
    $script:SectionIds = @('Sensitivity_Labels', 'Data_Loss_Prevention', 'Retention', 'Insider_Risk', 'Audit', 'eDiscovery', 'Communication_Compliance', 'DSPM_for_AI')

    function New-PpaDenseRawMap {
        @{
            Sensitivity_Labels       = Read-PpaFixtureJson 'Samples\sample-raw\labels.json'
            Data_Loss_Prevention     = Read-PpaFixtureJson 'Samples\sample-raw\dlp.json'
            Retention                = Read-PpaFixtureJson 'Samples\sample-raw\retention.json'
            Insider_Risk             = Read-PpaFixtureJson 'Samples\sample-raw\insiderrisk.json'
            Audit                    = Read-PpaFixtureJson 'Samples\sample-raw\audit.json'
            eDiscovery               = Read-PpaFixtureJson 'Samples\sample-raw\ediscovery.json'
            Communication_Compliance = Read-PpaFixtureJson 'Samples\sample-raw\commscompliance.json'
            DSPM_for_AI              = Read-PpaFixtureJson 'Samples\sample-raw\dspm.json'
        }
    }

    function New-PpaDenseSections {
        param($RawMap)
        $licMap = Get-PpaLicenseRequirements -Path (Join-Path $script:RepoRoot 'Data\license-requirements.json')
        $sitMap = Read-PpaFixtureJson 'Data\dlp-sit-tiers.json'
        $asOf   = [datetime]'2026-06-24'
        @(
            Invoke-PpaLabelAnalyzer          -Raw $RawMap.Sensitivity_Labels       -AsOf $asOf -LicenseMap $licMap
            Invoke-PpaDlpAnalyzer            -Raw $RawMap.Data_Loss_Prevention     -AsOf $asOf -LicenseMap $licMap -SitTierMap $sitMap
            Invoke-PpaRetentionAnalyzer      -Raw $RawMap.Retention                -LicenseMap $licMap
            Invoke-PpaInsiderRiskAnalyzer    -Raw $RawMap.Insider_Risk             -LicenseMap $licMap
            Invoke-PpaAuditAnalyzer          -Raw $RawMap.Audit                    -LicenseMap $licMap
            Invoke-PpaEdiscoveryAnalyzer     -Raw $RawMap.eDiscovery               -LicenseMap $licMap
            Invoke-PpaCommsComplianceAnalyzer -Raw $RawMap.Communication_Compliance -LicenseMap $licMap
            Invoke-PpaDspmAiAnalyzer         -Raw $RawMap.DSPM_for_AI              -LicenseMap $licMap -HasSiteLabels:$false
        )
    }

    function New-PpaGoldenModel {
        $rawMap = New-PpaDenseRawMap
        New-PpaSnapshotModel `
            -RawMap $rawMap `
            -Sections (New-PpaDenseSections $rawMap) `
            -Meta ([pscustomobject]@{ version = '2.0'; tenantId = 'contoso-dense-fixture' }) `
            -CapturedAt ([datetime]::new(2026, 7, 3, 14, 15, 0, [System.DateTimeKind]::Utc)) `
            -SnapshotId '9f8e7d6c-1a2b-3c4d-5e6f-708192a3b4c5' `
            -Environment ([ordered]@{ psEdition = 'Desktop'; psVersion = '5.1.golden'; modules = [ordered]@{ ExchangeOnlineManagement = '3.9.0' } })
    }

    $script:GoldenPath = Join-Path $script:RepoRoot 'Tests\Golden\dense-snapshot.json'

    # ---- order-sensitive structural deep-compare -------------------------------------
    # Compares two parsed/constructed trees INCLUDING object property order, so the
    # writer's ordering contract is pinned engine-independently. Handles the model
    # side (ordered hashtables / pscustomobjects) and the loaded side (pscustomobjects)
    # uniformly. Returns violation strings; empty means equal.
    function Get-PpaNodeProperty {
        param($Node)
        if ($Node -is [System.Collections.IDictionary]) {
            return @($Node.Keys | ForEach-Object { [pscustomobject]@{ Name = [string]$_; Value = $Node[$_] } })
        }
        return @($Node.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } })
    }
    function Test-PpaIsLeaf {
        param($Value)
        if ($null -eq $Value) { return $true }
        if ($Value -is [string] -or $Value -is [bool]) { return $true }
        if ($Value -is [System.ValueType]) { return $true }
        return $false
    }
    function Compare-PpaSnapshotNode {
        param($A, $B, [string]$Path = '$')
        $bad = New-Object System.Collections.Generic.List[string]
        $aLeaf = Test-PpaIsLeaf $A; $bLeaf = Test-PpaIsLeaf $B
        if ($aLeaf -ne $bLeaf) { $bad.Add("$Path : leaf/structure mismatch"); return $bad.ToArray() }
        if ($aLeaf) {
            if ($null -eq $A -or $null -eq $B) {
                if (-not ($null -eq $A -and $null -eq $B)) { $bad.Add("$Path : null vs value ('$A' / '$B')") }
            }
            elseif (($A -is [bool]) -ne ($B -is [bool])) { $bad.Add("$Path : bool/type mismatch ('$A' / '$B')") }
            elseif ($A -is [string] -or $B -is [string]) {
                if ([string]$A -cne [string]$B) { $bad.Add("$Path : '$A' <> '$B'") }
            }
            elseif ($A -ne $B) { $bad.Add("$Path : $A <> $B") }
            return $bad.ToArray()
        }
        $aIsArr = ($A -is [System.Collections.IEnumerable] -and $A -isnot [System.Collections.IDictionary] -and $A -isnot [System.Management.Automation.PSCustomObject])
        $bIsArr = ($B -is [System.Collections.IEnumerable] -and $B -isnot [System.Collections.IDictionary] -and $B -isnot [System.Management.Automation.PSCustomObject])
        if ($aIsArr -ne $bIsArr) { $bad.Add("$Path : array/object mismatch"); return $bad.ToArray() }
        if ($aIsArr) {
            $aa = @($A); $bb = @($B)
            if ($aa.Count -ne $bb.Count) { $bad.Add("$Path : array count $($aa.Count) <> $($bb.Count)"); return $bad.ToArray() }
            for ($i = 0; $i -lt $aa.Count; $i++) {
                foreach ($v in (Compare-PpaSnapshotNode -A $aa[$i] -B $bb[$i] -Path "$Path[$i]")) { $bad.Add($v) }
            }
            return $bad.ToArray()
        }
        $ap = Get-PpaNodeProperty $A; $bp = Get-PpaNodeProperty $B
        $aNames = @($ap | ForEach-Object { $_.Name }); $bNames = @($bp | ForEach-Object { $_.Name })
        if (($aNames -join '|') -cne ($bNames -join '|')) {
            $bad.Add("$Path : property order/set differs: [$($aNames -join ',')] <> [$($bNames -join ',')]")
            return $bad.ToArray()
        }
        for ($i = 0; $i -lt $ap.Count; $i++) {
            foreach ($v in (Compare-PpaSnapshotNode -A $ap[$i].Value -B $bp[$i].Value -Path "$Path.$($aNames[$i])")) { $bad.Add($v) }
        }
        return $bad.ToArray()
    }
}

Describe 'Snapshot model - schema v1.0 shape (3.2)' {
    BeforeAll { $script:M = New-PpaGoldenModel }

    It 'emits the top-level properties in the pinned schema order' {
        @((Get-PpaNodeProperty $script:M) | ForEach-Object { $_.Name }) | Should -Be @(
            'schemaVersion', 'toolVersion', 'snapshotId', 'capturedAt', 'tenantId', 'profile',
            'sectionsRun', 'redactionState', 'denylistVersion', 'environment',
            'collectorOutcomes', 'objects', 'findings')
    }
    It 'stamps schemaVersion 1.0, redactionState none, denylistVersion from the data file' {
        $script:M.schemaVersion.major | Should -Be 1
        $script:M.schemaVersion.minor | Should -Be 0
        $script:M.redactionState | Should -Be 'none'
        $script:M.denylistVersion | Should -Be '1.0'
    }
    It 'carries toolVersion, snapshotId, ISO-8601 UTC capturedAt and the fixture tenantId' {
        $script:M.toolVersion | Should -Be '2.0'
        $script:M.snapshotId | Should -Be '9f8e7d6c-1a2b-3c4d-5e6f-708192a3b4c5'
        $script:M.capturedAt | Should -Be '2026-07-03T14:15:00Z'
        $script:M.tenantId | Should -Be 'contoso-dense-fixture'
        $script:M.profile | Should -BeNullOrEmpty
    }
    It 'records sectionsRun in orchestration order' {
        @($script:M.sectionsRun) | Should -Be $script:SectionIds
    }
    It 'a crashed collector (attempted, raw is null) records Failed; never-attempted records NotRun' {
        # B-fix 1: Failed = attempted-and-errored (RawMap carries the id with $null);
        # NotRun = never attempted (RawMap has no entry for the id at all).
        $m = New-PpaSnapshotModel -RawMap @{ eDiscovery = $null } -Sections @() `
            -Meta ([pscustomobject]@{ version = '2.0'; tenantId = 't' }) `
            -CapturedAt ([datetime]::new(2026, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)) `
            -SnapshotId '00000000-1111-2222-3333-444444444444' -SectionIds @('eDiscovery', 'Audit')
        $m.collectorOutcomes['eDiscovery'] | Should -Be 'Failed'
        $m.collectorOutcomes['Audit'] | Should -Be 'NotRun'
    }
    It 'records every collector outcome from the fixtures, keys alphabetical' {
        $keys = @((Get-PpaNodeProperty $script:M.collectorOutcomes) | ForEach-Object { $_.Name })
        $keys | Should -Be @($script:SectionIds | Sort-Object)
        $script:M.collectorOutcomes['Insider_Risk'] | Should -Be 'CmdletUnavailable'
        $script:M.collectorOutcomes['Communication_Compliance'] | Should -Be 'Empty'
        $script:M.collectorOutcomes['Data_Loss_Prevention'] | Should -Be 'Populated'
    }
    It 'emits all 19 object types in alphabetical order' {
        $types = @((Get-PpaNodeProperty $script:M.objects) | ForEach-Object { $_.Name })
        $types.Count | Should -Be 19
        $types | Should -Be @($types | Sort-Object)
        $types | Should -Contain 'DlpPolicy'
        $types | Should -Contain 'AuditConfig'
        $types | Should -Contain 'DspmAiSummary'
    }
    It 'projects fixture objects into typed arrays' {
        @($script:M.objects['DlpPolicy']).Count | Should -Be 6
        @($script:M.objects['DlpRule']).Count | Should -Be 8
        @($script:M.objects['SensitivityLabel']).Count | Should -Be 6
        @($script:M.objects['EdiscoveryCase']).Count | Should -Be 2
        @($script:M.objects['InsiderRiskPolicy']).Count | Should -Be 0
        @($script:M.objects['AuditConfig']).Count | Should -Be 1
    }
    It 'flattens findings as {checkId,status,severity,section,title} records with null severity' {
        @($script:M.findings).Count | Should -BeGreaterThan 20
        $f = @($script:M.findings | Where-Object { $_.checkId -eq 'DLP-01' })
        $f.Count | Should -Be 1
        @((Get-PpaNodeProperty $f[0]) | ForEach-Object { $_.Name }) | Should -Be @('checkId', 'status', 'severity', 'section', 'title')
        $f[0].severity | Should -BeNullOrEmpty
        $f[0].section | Should -Be 'Data_Loss_Prevention'
        $f[0].status | Should -Be 'Informational'
    }
}

Describe 'Key stamping (3.3) per KEY_SOURCES.md' {
    BeforeAll { $script:M = New-PpaGoldenModel }

    It 'stamps _key and _keySource as the FIRST two properties of every object' {
        foreach ($t in @('DlpPolicy', 'AuditConfig', 'SensitivityLabel')) {
            foreach ($o in @($script:M.objects[$t])) {
                @((Get-PpaNodeProperty $o) | Select-Object -First 2 | ForEach-Object { $_.Name }) | Should -Be @('_key', '_keySource')
            }
        }
    }
    It 'keys on guid with source Guid when the item carries one' {
        $p = @($script:M.objects['DlpPolicy'])[0]
        $p._key | Should -Be 'guid-hipaa-phi-protection'
        $p._keySource | Should -Be 'Guid'
    }
    It 'keys singletons on the constant type name with source Name' {
        $a = @($script:M.objects['AuditConfig'])[0]
        $a._key | Should -Be 'AuditConfig'
        $a._keySource | Should -Be 'Name'
        $a.name | Should -Be 'AuditConfig'
        $a.unifiedAuditEnabled | Should -BeTrue
    }
    It 'falls back to Name when guid is absent or empty' {
        $torture = Read-PpaFixtureJson 'Samples\sample-raw\snapshot-torture.json'
        $m = New-PpaSnapshotModel -RawMap @{ Sensitivity_Labels = $torture } -Sections @() `
            -Meta ([pscustomobject]@{ version = '2.0'; tenantId = 't' }) `
            -CapturedAt ([datetime]::new(2026, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)) `
            -SnapshotId '00000000-1111-2222-3333-444444444444' -SectionIds @('Sensitivity_Labels')
        $p = @($m.objects['LabelPolicy'])[0]
        $p._key | Should -Be 'NoGuidPolicy'
        $p._keySource | Should -Be 'Name'
    }
    It 'disambiguates duplicate keys deterministically (#2, #3) and warns naming type and key' {
        $raw = [pscustomobject]@{
            outcome = 'Populated'
            cases = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(
                [pscustomobject]@{ name = 'Same'; guid = 'guid-dup'; caseStatus = 'Active' },
                [pscustomobject]@{ name = 'Same2'; guid = 'guid-dup'; caseStatus = 'Active' },
                [pscustomobject]@{ name = 'Same3'; guid = 'guid-dup'; caseStatus = 'Closed' }
            ) }
        }
        $warnings = @()
        $m = New-PpaSnapshotModel -RawMap @{ eDiscovery = $raw } -Sections @() `
            -Meta ([pscustomobject]@{ version = '2.0'; tenantId = 't' }) `
            -CapturedAt ([datetime]::new(2026, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)) `
            -SnapshotId '00000000-1111-2222-3333-444444444444' -SectionIds @('eDiscovery') `
            -WarningVariable warnings -WarningAction SilentlyContinue
        @($m.objects['EdiscoveryCase'] | ForEach-Object { $_._key }) | Should -Be @('guid-dup', 'guid-dup#2', 'guid-dup#3')
        @($warnings).Count | Should -Be 2
        [string]$warnings[0] | Should -Match 'EdiscoveryCase'
        [string]$warnings[0] | Should -Match 'guid-dup'
    }
}

Describe 'Golden file (6.2 #1) - ordering contract' {
    It 'the checked-in golden parses and structurally equals a fresh build (order-sensitive, both engines)' {
        Test-Path -LiteralPath $script:GoldenPath | Should -BeTrue
        $golden = [System.IO.File]::ReadAllText($script:GoldenPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $fresh  = ConvertTo-Json -InputObject (New-PpaGoldenModel) -Depth 16 | ConvertFrom-Json
        $violations = Compare-PpaSnapshotNode -A $fresh -B $golden
        ($violations -join "`n") | Should -BeNullOrEmpty
    }
    It 'matches the golden BYTES under PS 5.1 (canonical writer engine)' -Skip:($PSVersionTable.PSEdition -ne 'Desktop') {
        # Skip reason on 7+: ConvertTo-Json text formatting differs across engines;
        # the golden bytes are canonical Windows PowerShell 5.1 writer output. The
        # structural test above pins content and ordering on both engines.
        $fresh = ConvertTo-Json -InputObject (New-PpaGoldenModel) -Depth 16
        $golden = [System.IO.File]::ReadAllText($script:GoldenPath, [System.Text.Encoding]::UTF8)
        $fresh.TrimEnd("`r", "`n") | Should -Be ($golden.TrimEnd("`r", "`n"))
    }
    It 'serialization is deterministic: two builds produce identical text' {
        $a = ConvertTo-Json -InputObject (New-PpaGoldenModel) -Depth 16
        $b = ConvertTo-Json -InputObject (New-PpaGoldenModel) -Depth 16
        $a | Should -Be $b
    }
}

Describe 'Round-trip deep-compare (6.2 #2)' {
    BeforeAll {
        $script:TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('ppa-snap-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
    }
    AfterAll { Remove-Item -LiteralPath $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue }

    It 'dense fixture: export -> load -> deep-compare equals the source model' {
        # Compare the in-memory model DIRECTLY against the loaded snapshot: the
        # loader preserves date-like strings verbatim (-DateKind String on 7+),
        # so every leaf must round-trip exactly - values, order, and structure.
        $m = New-PpaGoldenModel
        $r = Export-PpaSnapshot -Model $m -Directory $script:TmpDir 6>$null
        $loaded = Import-PpaSnapshot -Path $r.SnapshotPath
        $violations = Compare-PpaSnapshotNode -A $m -B $loaded
        ($violations -join "`n") | Should -BeNullOrEmpty
    }
    It 'torture fixture: hostile strings, unicode and the depth canary survive intact' {
        $torture = Read-PpaFixtureJson 'Samples\sample-raw\snapshot-torture.json'
        $m = New-PpaSnapshotModel -RawMap @{ Sensitivity_Labels = $torture } -Sections @() `
            -Meta ([pscustomobject]@{ version = '2.0'; tenantId = 'torture' }) `
            -CapturedAt ([datetime]::new(2026, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)) `
            -SnapshotId 'abcdefab-1111-2222-3333-444444444444' -SectionIds @('Sensitivity_Labels')
        $r = Export-PpaSnapshot -Model $m -Directory $script:TmpDir 6>$null
        $loaded = Import-PpaSnapshot -Path $r.SnapshotPath
        $violations = Compare-PpaSnapshotNode -A $m -B $loaded
        ($violations -join "`n") | Should -BeNullOrEmpty
        @($loaded.objects.SensitivityLabel)[0].name | Should -Be 'Hostile "quoted" <angle> & back\slash label'
        @($loaded.objects.LabelContainerSummary)[0].groups.d1.d2.d3.d4.d5.d6.d7.d8.d9.canary | Should -Be 'reached'
    }
    It 'declared arrays stay arrays after load: single-item and empty' {
        $m = New-PpaGoldenModel
        $r = Export-PpaSnapshot -Model $m -Directory $script:TmpDir 6>$null
        $loaded = Import-PpaSnapshot -Path $r.SnapshotPath
        $pci = @($loaded.objects.DlpRule | Where-Object { $_.name -eq 'r-pci' })[0]
        , $pci.sits | Should -BeOfType [System.Array]
        @($pci.sits).Count | Should -Be 1
        $legacy2 = @($loaded.objects.DlpRule | Where-Object { $_.name -eq 'r-legacy-2' })[0]
        , $legacy2.sits | Should -BeOfType [System.Array]
        @($legacy2.sits).Count | Should -Be 0
    }
}

Describe 'Loader validation (3.4)' {
    BeforeAll {
        $script:TmpDir2 = Join-Path ([System.IO.Path]::GetTempPath()) ('ppa-snapv-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpDir2 -Force | Out-Null
        function Write-PpaTempJson([string]$Name, [string]$Text) {
            $p = Join-Path $script:TmpDir2 $Name
            [System.IO.File]::WriteAllText($p, $Text, (New-Object System.Text.UTF8Encoding($false)))
            return $p
        }
    }
    AfterAll { Remove-Item -LiteralPath $script:TmpDir2 -Recurse -Force -ErrorAction SilentlyContinue }

    It 'refuses a missing file with an actionable message' {
        { Import-PpaSnapshot -Path (Join-Path $script:TmpDir2 'nope.json') } | Should -Throw '*not found*'
    }
    It 'refuses invalid JSON with an actionable message' {
        $p = Write-PpaTempJson 'bad.json' '{ not json'
        { Import-PpaSnapshot -Path $p } | Should -Throw '*not valid JSON*'
    }
    It 'refuses a JSON file without schemaVersion (not a PPA snapshot)' {
        $p = Write-PpaTempJson 'noschema.json' '{ "hello": 1 }'
        { Import-PpaSnapshot -Path $p } | Should -Throw '*schemaVersion*'
    }
    It 'refuses a snapshot missing required top-level fields, naming them' {
        $p = Write-PpaTempJson 'partial.json' '{ "schemaVersion": { "major": 1, "minor": 0 }, "snapshotId": "x" }'
        { Import-PpaSnapshot -Path $p } | Should -Throw '*objects*'
    }
    It 'refuses a different major version with the 3.5 message' {
        $p = Write-PpaTempJson 'major2.json' '{ "schemaVersion": { "major": 2, "minor": 0 }, "snapshotId": "x", "capturedAt": "c", "sectionsRun": [], "collectorOutcomes": {}, "objects": {}, "findings": [] }'
        { Import-PpaSnapshot -Path $p } | Should -Throw '*schema v2*'
    }
    It 'reads a newer minor tolerantly with a single summary warning' {
        $p = Write-PpaTempJson 'minor9.json' '{ "schemaVersion": { "major": 1, "minor": 9 }, "snapshotId": "x", "capturedAt": "c", "tenantId": null, "sectionsRun": [], "collectorOutcomes": {}, "objects": {}, "findings": [], "futureField": true }'
        $warnings = @()
        $loaded = Import-PpaSnapshot -Path $p -WarningVariable warnings -WarningAction SilentlyContinue
        $loaded.snapshotId | Should -Be 'x'
        @($warnings).Count | Should -Be 1
        [string]$warnings[0] | Should -Match 'newer minor'
    }
}

Describe 'Snapshot emission (3.1)' {
    BeforeAll {
        $script:TmpDir3 = Join-Path ([System.IO.Path]::GetTempPath()) ('ppa-snape-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpDir3 -Force | Out-Null
    }
    AfterAll { Remove-Item -LiteralPath $script:TmpDir3 -Recurse -Force -ErrorAction SilentlyContinue }

    It 'names the file PPA-Snapshot_<tenantIdShort>_<capturedAtCompact>Z_<snapshotId8>.json' {
        $r = Export-PpaSnapshot -Model (New-PpaGoldenModel) -Directory $script:TmpDir3 6>$null
        [System.IO.Path]::GetFileName($r.SnapshotPath) | Should -Be 'PPA-Snapshot_contosod_20260703T141500Z_9f8e7d6c.json'
        Test-Path -LiteralPath $r.SnapshotPath | Should -BeTrue
    }
    It 'falls back to tenantIdShort "unknown" when tenantId is null' {
        $torture = Read-PpaFixtureJson 'Samples\sample-raw\snapshot-torture.json'
        $m = New-PpaSnapshotModel -RawMap @{ Sensitivity_Labels = $torture } -Sections @() `
            -Meta ([pscustomobject]@{ version = '2.0' }) `
            -CapturedAt ([datetime]::new(2026, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)) `
            -SnapshotId 'abcdefab-1111-2222-3333-444444444444' -SectionIds @('Sensitivity_Labels')
        $r = Export-PpaSnapshot -Model $m -Directory $script:TmpDir3 6>$null
        [System.IO.Path]::GetFileName($r.SnapshotPath) | Should -Be 'PPA-Snapshot_unknown_20260101T000000Z_abcdefab.json'
    }
    It 'emits the one-line unredacted-contents console notice naming what it contains' {
        $notice = Export-PpaSnapshot -Model (New-PpaGoldenModel) -Directory $script:TmpDir3 6>&1 |
            Where-Object { "$_" -match 'unredacted UPNs and scope identities' }
        @($notice).Count | Should -Be 1
        "$notice" | Should -Match 'treat as engagement-confidential'
    }
    It '-IncludeRawCapture writes a separate PPA-RawCapture_ debug file' {
        $rawMap = New-PpaDenseRawMap
        $r = Export-PpaSnapshot -Model (New-PpaGoldenModel) -Directory $script:TmpDir3 -RawMap $rawMap -IncludeRawCapture 6>$null
        $r.RawCapturePath | Should -Not -BeNullOrEmpty
        [System.IO.Path]::GetFileName($r.RawCapturePath) | Should -Be 'PPA-RawCapture_contosod_20260703T141500Z_9f8e7d6c.json'
        Test-Path -LiteralPath $r.RawCapturePath | Should -BeTrue
        # And it is outside the schema: no schemaVersion in the raw capture.
        $rawParsed = [System.IO.File]::ReadAllText($r.RawCapturePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $rawParsed.PSObject.Properties.Name | Should -Not -Contain 'schemaVersion'
    }
    It 'without -IncludeRawCapture no raw capture file is written' {
        $r = Export-PpaSnapshot -Model (New-PpaGoldenModel) -Directory $script:TmpDir3 6>$null
        $r.RawCapturePath | Should -BeNullOrEmpty
        @(Get-ChildItem -Path $script:TmpDir3 -Filter 'PPA-RawCapture_*').Count | Should -Be 1
    }
}

Describe 'Scope display mapping never leaks into snapshots (Wave 5 cleanup Part 3)' {
    # Delta-safety guard for the Teamwork -> Teams DISPLAY mapping: snapshots
    # serialize collector output verbatim, so the SensitivityLabel scopes array
    # must keep the raw canonical value. If a future change maps names before the
    # display boundary, old raw snapshots would diff against new friendly ones -
    # a pure display change masquerading as a data change. This guard pins the
    # raw side of the pair (the friendly render side is pinned in
    # Analyzer.Labels.Tests.ps1 against the SAME fixture).
    It 'the fixture label with raw scope Teamwork snapshots as Teamwork, never Teams' {
        $rawMap = @{ Sensitivity_Labels = (Read-PpaFixtureJson 'Samples\sample-raw\labels-autolabel-cases.json') }
        $model = New-PpaSnapshotModel `
            -RawMap $rawMap -Sections @() `
            -Meta ([pscustomobject]@{ version = '2.0'; tenantId = 'scope-map-guard-fixture' }) `
            -CapturedAt ([datetime]::new(2026, 7, 6, 12, 0, 0, [System.DateTimeKind]::Utc)) `
            -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0001' `
            -SectionIds @('Sensitivity_Labels') `
            -Environment ([ordered]@{ psEdition = 'Desktop'; psVersion = '5.1.guard'; modules = [ordered]@{} })
        $meetings = @($model.objects.SensitivityLabel | Where-Object { $_._key -eq 'guid-al-cases-meetings' })
        $meetings.Count | Should -Be 1
        @($meetings[0].scopes) | Should -Contain 'Teamwork'
        @($meetings[0].scopes) | Should -Not -Contain 'Teams'
    }
}
