# Delta.Tests.ps1 - Wave 4 Part C pins: delta mode (spec section 4 + tests 5-10 of
# 6.2). Delta is PS 7+ only: every test here SKIPS on Windows PowerShell 5.1 with an
# explicit reason, EXCEPT the engine-gate refusal test, which exercises the real
# refusal on 5.1 and the injected version check on 7+.
# Pester 5. ASCII-only source (file must still PARSE under 5.1 - the module loader
# dot-sources everything on both engines).

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    foreach ($f in (Get-ChildItem -Path (Join-Path $script:RepoRoot 'Private') -Recurse -Filter '*.ps1')) { . $f.FullName }

    $script:SkipReason = 'Delta mode is PS 7+ only (spec section 1 runtime matrix); writer-side coverage runs under 5.1.'
    function Skip-OnPs51 {
        if ($PSVersionTable.PSEdition -eq 'Desktop') { Set-ItResult -Skipped -Because $script:SkipReason }
    }

    $script:FixA = Join-Path $script:RepoRoot 'Samples\delta-fixtures\dense-delta-A.json'
    $script:FixB = Join-Path $script:RepoRoot 'Samples\delta-fixtures\dense-delta-B.json'

    $script:TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('ppa-delta-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null

    function Get-PpaTestDelta {
        param([switch]$AllowTenantMismatch)
        $a = Import-PpaSnapshot -Path $script:FixA
        $b = Import-PpaSnapshot -Path $script:FixB
        Compare-PpaSnapshotPair -From $a -To $b -AllowTenantMismatch:$AllowTenantMismatch -WarningAction SilentlyContinue
    }
    function Get-PpaDeltaSection {
        param($Delta, [string]$Id)
        return @($Delta.sections | Where-Object { $_.id -eq $Id })[0]
    }
    # Build a minimal one-section snapshot pair for synthetic cases by mutating
    # parsed copies of fixture A.
    function Get-PpaSnapshotCopy {
        param([string]$Path)
        return (Import-PpaSnapshot -Path $Path)
    }
}

AfterAll {
    if ($script:TmpDir -and (Test-Path -LiteralPath $script:TmpDir)) {
        Remove-Item -LiteralPath $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Engine gate (spec section 1) - runs on BOTH engines' {
    It 'refuses delta below PS 7.5 with the ruled message (real on 5.1, injected on 7+)' {
        # Injectable version check: redefining Test-PpaDeltaEngine simulates a
        # too-old host without needing one; on a real 5.1 host the injection is a
        # no-op lie that matches reality. Floor is 7.5 - the loader depends on
        # ConvertFrom-Json -DateKind String (C-fix 1).
        function Test-PpaDeltaEngine { return $false }
        { Invoke-PpaDelta -FromPath $script:FixA -ToPath $script:FixB -OutputPath $script:TmpDir } |
            Should -Throw '*Delta mode requires PowerShell 7.5 or later (run under pwsh). Snapshot capture works on Windows PowerShell 5.1; comparing snapshots does not.*'
    }
}

Describe 'Delta fixture pair - regeneration matches the checked-in pair (6.1)' {
    It 'checked-in pairs (torture + showcase) exist and regeneration deep-compares equal (drift guard)' {
        Skip-OnPs51
        Test-Path -LiteralPath $script:FixA | Should -BeTrue
        Test-Path -LiteralPath $script:FixB | Should -BeTrue
        $regen = Join-Path $script:TmpDir 'regen'
        & (Join-Path $script:RepoRoot 'tools\New-DeltaFixturePair.ps1') -OutDir $regen | Out-Null
        foreach ($n in @('dense-delta-A.json', 'dense-delta-B.json', 'showcase-delta-A.json', 'showcase-delta-B.json')) {
            $fresh = [System.IO.File]::ReadAllText((Join-Path $regen $n), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            $gold  = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot "Samples\delta-fixtures\$n"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            (ConvertTo-Json -InputObject $fresh -Depth 16) | Should -Be (ConvertTo-Json -InputObject $gold -Depth 16)
        }
    }
    It 'the showcase pair is degradation-free and yields a clean, presentable delta (C-fix 7)' {
        Skip-OnPs51
        $a = Import-PpaSnapshot -Path (Join-Path $script:RepoRoot 'Samples\delta-fixtures\showcase-delta-A.json')
        $b = Import-PpaSnapshot -Path (Join-Path $script:RepoRoot 'Samples\delta-fixtures\showcase-delta-B.json')
        $d = Compare-PpaSnapshotPair -From $a -To $b -WarningAction SilentlyContinue
        @($d.sections | Where-Object { $_.state -ne 'Compared' }).Count | Should -Be 0
        $d.spanDays | Should -Be 91
        $dlp = @($d.sections | Where-Object { $_.id -eq 'Data_Loss_Prevention' })[0]
        @($dlp.added).Count | Should -Be 1
        $labels = @($d.sections | Where-Object { $_.id -eq 'Sensitivity_Labels' })[0]
        @($labels.added).Count | Should -Be 1
        $ret = @($d.sections | Where-Object { $_.id -eq 'Retention' })[0]
        @($ret.modified | Where-Object { $_.renamed -and $_.renameTo -eq 'HR Records EU - 7yr' }).Count | Should -Be 1
        # No visibility block content at all: the report leads with real change.
        $html = Export-PpaDeltaReport -Delta $d
        $html | Should -Not -Match 'id="delta-visibility"'
    }
}

Describe 'Pre-compare validation (4.2)' {
    It 'refuses a tenant mismatch by default and proceeds with -AllowTenantMismatch' {
        Skip-OnPs51
        $a = Get-PpaSnapshotCopy $script:FixA
        $b = Get-PpaSnapshotCopy $script:FixB
        $b.tenantId = 'some-other-tenant'
        { Compare-PpaSnapshotPair -From $a -To $b } | Should -Throw '*tenant*'
        $d = Compare-PpaSnapshotPair -From $a -To $b -AllowTenantMismatch -WarningAction SilentlyContinue
        $d | Should -Not -BeNullOrEmpty
    }
    It 'warns and proceeds when either tenantId is absent' {
        Skip-OnPs51
        $a = Get-PpaSnapshotCopy $script:FixA
        $b = Get-PpaSnapshotCopy $script:FixB
        $a.tenantId = $null
        $warnings = @()
        $d = Compare-PpaSnapshotPair -From $a -To $b -WarningVariable warnings -WarningAction SilentlyContinue
        $d | Should -Not -BeNullOrEmpty
        @($warnings | Where-Object { "$_" -match 'tenantId' }).Count | Should -BeGreaterThan 0
    }
    It 'warns on reversed capturedAt order and does NOT auto-swap' {
        Skip-OnPs51
        $a = Get-PpaSnapshotCopy $script:FixB   # newer as From
        $b = Get-PpaSnapshotCopy $script:FixA
        $warnings = @()
        $d = Compare-PpaSnapshotPair -From $a -To $b -WarningVariable warnings -WarningAction SilentlyContinue
        @($warnings | Where-Object { "$_" -match 'newer' }).Count | Should -BeGreaterThan 0
        $d.from.snapshotId | Should -Be $a.snapshotId
        $d.spanDays | Should -Be -41
    }
    It 'computes the 41-day span of the fixture pair' {
        Skip-OnPs51
        (Get-PpaTestDelta).spanDays | Should -Be 41
    }
    It 'shows the informational denylist-version note when recorded versions differ' {
        Skip-OnPs51
        $d = Get-PpaTestDelta
        $d.denylistNote | Should -Match '0.9'
        $d.denylistNote | Should -Match 'current'
    }
}

Describe 'Version gates (6.2 #8)' {
    It 'refuses a cross-major snapshot with the 3.5 message' {
        Skip-OnPs51
        $text = [System.IO.File]::ReadAllText($script:FixA, [System.Text.Encoding]::UTF8)
        $p = Join-Path $script:TmpDir 'major9.json'
        [System.IO.File]::WriteAllText($p, ($text -replace '"major":\s*1', '"major": 9'), (New-Object System.Text.UTF8Encoding($false)))
        { Import-PpaSnapshot -Path $p } | Should -Throw '*schema v9*'
        { Import-PpaSnapshot -Path $p } | Should -Throw '*Re-run the newer tool*'
    }
    It 'reads a newer-minor snapshot tolerantly with one summary warning' {
        Skip-OnPs51
        $text = [System.IO.File]::ReadAllText($script:FixA, [System.Text.Encoding]::UTF8)
        $p = Join-Path $script:TmpDir 'minor7.json'
        [System.IO.File]::WriteAllText($p, ($text -replace '"minor":\s*0', '"minor": 7'), (New-Object System.Text.UTF8Encoding($false)))
        $warnings = @()
        $loaded = Import-PpaSnapshot -Path $p -WarningVariable warnings -WarningAction SilentlyContinue
        $loaded.snapshotId | Should -Not -BeNullOrEmpty
        @($warnings).Count | Should -Be 1
    }
}

Describe 'Section semantics (4.3 / 6.2 #6)' {
    BeforeAll { if ($PSVersionTable.PSEdition -ne 'Desktop') { $script:D = Get-PpaTestDelta } }

    It 'a section missing from one sectionsRun is NotCompared with a reason naming the side' {
        Skip-OnPs51
        $s = Get-PpaDeltaSection $script:D 'Audit'
        $s.state | Should -Be 'NotCompared'
        $s.reason | Should -Match 'DeltaTo'
        $s.reason | Should -Match 'Audit'
    }
    It 'NEVER mass-adds/removes objects from section absence' {
        Skip-OnPs51
        $s = Get-PpaDeltaSection $script:D 'Audit'
        @($s.added).Count | Should -Be 0
        @($s.removed).Count | Should -Be 0
    }
}

Describe 'Visibility precedence in all three directions (6.2 #5)' {
    BeforeAll { if ($PSVersionTable.PSEdition -ne 'Desktop') { $script:D = Get-PpaTestDelta } }

    It 'readable -> degraded (eDiscovery Populated -> AccessDenied): object diff suppressed' {
        Skip-OnPs51
        $s = Get-PpaDeltaSection $script:D 'eDiscovery'
        $s.state | Should -Be 'VisibilityChanged'
        $s.fromOutcome | Should -Be 'Populated'
        $s.toOutcome | Should -Be 'AccessDenied'
        @($s.added).Count + @($s.removed).Count + @($s.modified).Count | Should -Be 0
    }
    It 'degraded -> readable (Comms AccessDenied -> Empty) notes what became observable' {
        Skip-OnPs51
        $s = Get-PpaDeltaSection $script:D 'Communication_Compliance'
        $s.state | Should -Be 'VisibilityChanged'
        $s.fromOutcome | Should -Be 'AccessDenied'
        $s.toOutcome | Should -Be 'Empty'
        $s.visibilityNote | Should -Match 'observable'
    }
    It 'degraded -> degraded (Insider Risk CmdletUnavailable both sides) is a visibility record, not a diff' {
        Skip-OnPs51
        $s = Get-PpaDeltaSection $script:D 'Insider_Risk'
        $s.state | Should -Be 'VisibilityChanged'
        $s.fromOutcome | Should -Be 'CmdletUnavailable'
        $s.toOutcome | Should -Be 'CmdletUnavailable'
    }
    It 'equal degraded outcomes read as visibility UNCHANGED - never implying a change (C-fix 3)' {
        Skip-OnPs51
        $s = Get-PpaDeltaSection $script:D 'Insider_Risk'
        $s.visibilityNote | Should -Be 'visibility unchanged - not readable on either side (CmdletUnavailable)'
    }
}

Describe 'One-sided checks are never silent (C-fix 2)' {
    It 'a check present only in the TO snapshot notices the older side, listed by checkId' {
        Skip-OnPs51
        $a = Get-PpaSnapshotCopy $script:FixA
        $b = Get-PpaSnapshotCopy $script:FixA
        $a.findings = @($a.findings | Where-Object { [string]$_.checkId -ne 'DLP-04' })
        $d = Compare-PpaSnapshotPair -From $a -To $b -WarningAction SilentlyContinue
        $s = Get-PpaDeltaSection $d 'Data_Loss_Prevention'
        $n = @($s.findingNotices | Where-Object { $_.checkId -eq 'DLP-04' })
        $n.Count | Should -Be 1
        $n[0].reason | Should -Be 'check not present in the older snapshot - likely tool version difference'
        @($s.findingChanges | Where-Object { $_.checkId -eq 'DLP-04' }).Count | Should -Be 0
    }
    It 'a check present only in the FROM snapshot notices the newer side' {
        Skip-OnPs51
        $a = Get-PpaSnapshotCopy $script:FixA
        $b = Get-PpaSnapshotCopy $script:FixA
        $b.findings = @($b.findings | Where-Object { [string]$_.checkId -ne 'DLP-04' })
        $d = Compare-PpaSnapshotPair -From $a -To $b -WarningAction SilentlyContinue
        $s = Get-PpaDeltaSection $d 'Data_Loss_Prevention'
        $n = @($s.findingNotices | Where-Object { $_.checkId -eq 'DLP-04' })
        $n.Count | Should -Be 1
        $n[0].reason | Should -Be 'check not present in the newer snapshot - likely tool version difference'
    }
}

Describe 'Compare semantics: add / remove / rename / arrays / denylist (4.3-4.4)' {
    BeforeAll { if ($PSVersionTable.PSEdition -ne 'Desktop') { $script:D = Get-PpaTestDelta } }

    It 'detects the added DLP policy' {
        Skip-OnPs51
        $s = Get-PpaDeltaSection $script:D 'Data_Loss_Prevention'
        @($s.added | Where-Object { $_.name -eq 'Shadow IT Guard' }).Count | Should -Be 1
    }
    It 'detects the removed retention label' {
        Skip-OnPs51
        $s = Get-PpaDeltaSection $script:D 'Retention'
        @($s.removed | Where-Object { $_.name -eq 'Project-5y' }).Count | Should -Be 1
    }
    It 'classifies rename-with-same-Guid as Modified with a rename annotation, never Removed+Added' {
        Skip-OnPs51
        $s = Get-PpaDeltaSection $script:D 'Data_Loss_Prevention'
        $ren = @($s.modified | Where-Object { $_.renamed -and $_.key -eq 'guid-ssn-guard' })
        $ren.Count | Should -Be 1
        $ren[0].renameFrom | Should -Be 'SSN Guard'
        $ren[0].renameTo | Should -Be 'US SSN Guard'
        @($s.added   | Where-Object { $_.name -eq 'US SSN Guard' }).Count | Should -Be 0
        @($s.removed | Where-Object { $_.name -eq 'SSN Guard' }).Count | Should -Be 0
    }
    It 'order-only change in a declared array is Unchanged; membership change is Modified' {
        Skip-OnPs51
        $ret = Get-PpaDeltaSection $script:D 'Retention'
        @($ret.modified | Where-Object { $_.key -eq 'guid-finance-records-10yr' }).Count | Should -Be 0
        $dlp = Get-PpaDeltaSection $script:D 'Data_Loss_Prevention'
        $rule = @($dlp.modified | Where-Object { $_.key -eq 'guid-r-fin' })
        $rule.Count | Should -Be 1
        @($rule[0].changes | Where-Object { $_.property -eq 'sits' }).Count | Should -Be 1
    }
    It 'sim -> enforce mode flip is Modified and PROMOTED via the significant-property registry' {
        Skip-OnPs51
        $s = Get-PpaDeltaSection $script:D 'Data_Loss_Prevention'
        $m = @($s.modified | Where-Object { $_.key -eq 'guid-broad-pii-new' })
        $m.Count | Should -Be 1
        $chg = @($m[0].changes | Where-Object { $_.property -eq 'mode' })[0]
        $chg.from | Should -Be 'TestWithoutNotifications'
        $chg.to | Should -Be 'Enable'
        $chg.significant | Should -BeTrue
    }
    It 'a change ONLY in denylisted properties classifies as Unchanged (6.2 #7)' {
        Skip-OnPs51
        $s = Get-PpaDeltaSection $script:D 'Sensitivity_Labels'
        @($s.modified).Count | Should -Be 0
        @($s.added).Count | Should -Be 0
        @($s.removed).Count | Should -Be 0
        $s.unchangedCount | Should -Be 10
    }
    It 'reports the per-section unchanged count (confidence signal)' {
        Skip-OnPs51
        (Get-PpaDeltaSection $script:D 'Data_Loss_Prevention').unchangedCount | Should -Be 11
        (Get-PpaDeltaSection $script:D 'Retention').unchangedCount | Should -Be 11
    }
    It 'FindingChanged captures a status flip; severity is reserved and never compared while null' {
        Skip-OnPs51
        $s = Get-PpaDeltaSection $script:D 'Data_Loss_Prevention'
        $fc = @($s.findingChanges | Where-Object { $_.checkId -eq 'DLP-02' })
        $fc.Count | Should -Be 1
        $fc[0].fromStatus | Should -Be 'Improvement'
        $fc[0].toStatus | Should -Be 'OK'
        $fc[0].PSObject.Properties.Name | Should -Not -Contain 'fromSeverity'
    }
}

Describe 'Opaque identity contract (A.5 addendum) - synthetic reconciliation cases' {
    It 'reconciles key-divergent objects by NON-EMPTY STRING equality on a slug guid' {
        Skip-OnPs51
        # Old-writer style: Name-keyed objects that carry a slug guid; rename changes
        # the key, and only opaque guid equality can pair them.
        $a = Get-PpaSnapshotCopy $script:FixA
        $b = Get-PpaSnapshotCopy $script:FixA
        $b.snapshotId = 'bbbbbbbb-0000-0000-0000-00000000000b'
        $objA = @($a.objects.DlpPolicy)[0]
        $objB = @($b.objects.DlpPolicy)[0]
        $objA._key = 'HIPAA Policy Old'; $objA._keySource = 'Name'; $objA.name = 'HIPAA Policy Old'
        $objB._key = 'HIPAA Policy New'; $objB._keySource = 'Name'; $objB.name = 'HIPAA Policy New'
        # both keep guid 'guid-hipaa-phi-protection' (fixture slug - opaque contract)
        $d = Compare-PpaSnapshotPair -From $a -To $b -WarningAction SilentlyContinue
        $s = Get-PpaDeltaSection $d 'Data_Loss_Prevention'
        $ren = @($s.modified | Where-Object { $_.renamed -and $_.renameTo -eq 'HIPAA Policy New' })
        $ren.Count | Should -Be 1
        @($s.added).Count | Should -Be 0
        @($s.removed).Count | Should -Be 0
    }
    It 'never pairs on EMPTY guids (empty is not an identity)' {
        Skip-OnPs51
        $a = Get-PpaSnapshotCopy $script:FixA
        $b = Get-PpaSnapshotCopy $script:FixA
        $objA = @($a.objects.DlpPolicy)[0]
        $objB = @($b.objects.DlpPolicy)[0]
        $objA._key = 'Old A'; $objA._keySource = 'Name'; $objA.name = 'Old A'; $objA.guid = ''
        $objB._key = 'New B'; $objB._keySource = 'Name'; $objB.name = 'New B'; $objB.guid = ''
        $d = Compare-PpaSnapshotPair -From $a -To $b -WarningAction SilentlyContinue
        $s = Get-PpaDeltaSection $d 'Data_Loss_Prevention'
        @($s.added   | Where-Object { $_.name -eq 'New B' }).Count | Should -Be 1
        @($s.removed | Where-Object { $_.name -eq 'Old A' }).Count | Should -Be 1
        @($s.modified | Where-Object { $_.renamed }).Count | Should -Be 0
    }
}

Describe 'Empty-string vs absent-property equivalence (A.5 carry-forward)' {
    It 'a property moving between absent and empty string is never a Modified' {
        Skip-OnPs51
        # testModeSince is '' on the HIPAA policy (enforcing, MinValue-normalized
        # upstream); dropping the property entirely must compare as identical.
        $a = Get-PpaSnapshotCopy $script:FixA
        $b = Get-PpaSnapshotCopy $script:FixA
        $objB = @($b.objects.DlpPolicy | Where-Object { $_._key -eq 'guid-hipaa-phi-protection' })[0]
        $objB.testModeSince | Should -Be ''
        $objB.PSObject.Properties.Remove('testModeSince')
        $d = Compare-PpaSnapshotPair -From $a -To $b -WarningAction SilentlyContinue
        $s = Get-PpaDeltaSection $d 'Data_Loss_Prevention'
        @($s.modified).Count | Should -Be 0
        @($s.added).Count + @($s.removed).Count | Should -Be 0
    }
}

Describe 'Identity-failure heuristic (6.2 #10)' {
    It 'Added>0, Removed>0, Modified=0, Unchanged=0 in a section raises the keying warning' {
        Skip-OnPs51
        $a = Get-PpaSnapshotCopy $script:FixA
        $b = Get-PpaSnapshotCopy $script:FixA
        # eDiscovery on A-fixture is Populated with 2 cases; replace B's with 2
        # entirely different keys and no guid overlap.
        $b.objects.EdiscoveryCase = @(
            [pscustomobject]@{ _key = 'guid-case-p'; _keySource = 'Guid'; name = 'Case-P'; guid = 'guid-case-p'; caseStatus = 'Active' },
            [pscustomobject]@{ _key = 'guid-case-q'; _keySource = 'Guid'; name = 'Case-Q'; guid = 'guid-case-q'; caseStatus = 'Active' }
        )
        $d = Compare-PpaSnapshotPair -From $a -To $b -WarningAction SilentlyContinue
        $s = Get-PpaDeltaSection $d 'eDiscovery'
        $s.identityWarning | Should -BeTrue
        (Get-PpaDeltaSection $d 'Retention').identityWarning | Should -BeFalse
    }
}

Describe 'Delta report render (4.5) + redaction (6.2 #14, delta half)' {
    It 'writes the delta HTML with header ids, span, unchanged counts and notices' {
        Skip-OnPs51
        $r = Invoke-PpaDelta -FromPath $script:FixA -ToPath $script:FixB -OutputPath $script:TmpDir -WarningAction SilentlyContinue 6>$null
        Test-Path -LiteralPath $r.DeltaPath | Should -BeTrue
        $html = [System.IO.File]::ReadAllText($r.DeltaPath, [System.Text.Encoding]::UTF8)
        $html | Should -Match 'aaaa1111'      # from snapshotId
        $html | Should -Match 'bbbb2222'      # to snapshotId
        $html | Should -Match '41 days'
        $html | Should -Match 'unchanged'
        $html | Should -Match 'Shadow IT Guard'
        $html | Should -Match 'US SSN Guard'
        $html | Should -Match 'Not compared'
    }
    It 'embeds the SAME shared CSS block as the main report (C-fix 4, structural)' {
        Skip-OnPs51
        $shared = Get-PpaSharedReportCss
        $shared | Should -Match '@media print\{'
        $deltaHtml = Export-PpaDeltaReport -Delta (Get-PpaTestDelta)
        $deltaHtml.Contains($shared) | Should -BeTrue
        (Get-PpaReportHead).Contains($shared) | Should -BeTrue
    }
    It 'groups ALL visibility and not-compared notices into one Assessment visibility block (C-fix 6)' {
        Skip-OnPs51
        $html = Export-PpaDeltaReport -Delta (Get-PpaTestDelta)
        $html | Should -Match 'id="delta-visibility"'
        # Notices live in the block, never as interleaved per-section cards:
        $html | Should -Not -Match 'id="delta-Audit"'
        $html | Should -Not -Match 'id="delta-Insider_Risk"'
        $html | Should -Not -Match 'id="delta-eDiscovery"'
        $html | Should -Not -Match 'id="delta-Communication_Compliance"'
        $block = ($html -split 'id="delta-visibility"')[1]
        $block = ($block -split '</div></div>')[0]
        $block | Should -Match 'Audit'
        $block | Should -Match 'Insider Risk'
        $block | Should -Match 'not compared'
        $block | Should -Match 'visibility unchanged - not readable on either side \(CmdletUnavailable\)'
    }
    It 'renders the identity-failure banner text with a _keySource pointer when triggered' {
        Skip-OnPs51
        $a = Get-PpaSnapshotCopy $script:FixA
        $b = Get-PpaSnapshotCopy $script:FixA
        $b.objects.EdiscoveryCase = @(
            [pscustomobject]@{ _key = 'x1'; _keySource = 'Name'; name = 'x1'; guid = ''; caseStatus = 'Active' },
            [pscustomobject]@{ _key = 'x2'; _keySource = 'Name'; name = 'x2'; guid = ''; caseStatus = 'Active' }
        )
        $d = Compare-PpaSnapshotPair -From $a -To $b -WarningAction SilentlyContinue
        $html = Export-PpaDeltaReport -Delta $d
        $html | Should -Match '_keySource'
        $html | Should -Match 'identity'
    }
    It 'pseudonymizes policy names in the delta report under -Redact -RedactNames' {
        Skip-OnPs51
        $r = Invoke-PpaDelta -FromPath $script:FixA -ToPath $script:FixB -OutputPath $script:TmpDir -Redact -RedactNames -WarningAction SilentlyContinue 6>$null
        $html = [System.IO.File]::ReadAllText($r.DeltaPath, [System.Text.Encoding]::UTF8)
        $html | Should -Not -Match 'Broad PII'
        $html | Should -Not -Match 'Shadow IT Guard'
        $html | Should -Match 'Policy-\d\d'
    }
    It 'the public entry point drives delta end to end (file-in, HTML-out, no session)' {
        Skip-OnPs51
        Import-Module (Join-Path $script:RepoRoot 'PurviewPostureAnalyzer.psd1') -Force
        try {
            $r = Invoke-PurviewPostureAnalyzer -DeltaFrom $script:FixA -DeltaTo $script:FixB -OutputPath $script:TmpDir -WarningAction SilentlyContinue 6>$null
            Test-Path -LiteralPath $r.DeltaPath | Should -BeTrue
            [System.IO.Path]::GetFileName($r.DeltaPath) | Should -BeLike 'PPA-Delta_*.html'
        }
        finally { Remove-Module PurviewPostureAnalyzer -Force -ErrorAction SilentlyContinue }
    }
}
