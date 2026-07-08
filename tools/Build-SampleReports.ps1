# Build-SampleReports.ps1 - render every fixture-driven sample report for browser review.
# The human validation loop for the render layer: no tenant, no network, just fixtures
# through the real assemble -> render pipeline. Output goes to a gitignored folder and
# the script prints every file path it wrote at the end.
#
#   pwsh -File tools/Build-SampleReports.ps1
#
# ASCII-only source (Windows PowerShell 5.1).
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $root 'Samples\sample-reports' }

# Dot-source the whole Private tree (same approach as the module loader) so this script
# always sees the current render/model surface without maintaining an import list.
foreach ($file in (Get-ChildItem -Path (Join-Path $root 'Private') -Recurse -Filter '*.ps1')) { . $file.FullName }

if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$written = New-Object System.Collections.Generic.List[string]

function Read-PpaFixture([string]$RelPath) {
    [System.IO.File]::ReadAllText((Join-Path $root $RelPath), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Write-PpaSampleReport {
    param([string]$Name, [string]$Html)
    $path = Join-Path $OutDir $Name
    [System.IO.File]::WriteAllText($path, $Html, (New-Object System.Text.UTF8Encoding($false)))
    $written.Add($path)
}

# ---- 1. Standard fixture (the Wave 1/2 sample: Northwind Health, 21 findings) ----
$std = Read-PpaFixture 'Samples\sample-normalized.json'
$stdNorm = ConvertTo-PpaNormalized -Meta $std.meta -Licensing $std.licensing -Sections $std.sections -Observations $std.observations
Write-PpaSampleReport -Name 'sample-standard.html' -Html (Export-PpaHtmlReport -Normalized $stdNorm -IsSample)

# ---- 2. Dense fixture (Contoso Pharmaceuticals, 26 findings, every severity) ----
# Wave 4 Part D: the dense sample carries the coverage matrix, projected from the
# dense RAW fixtures (same source as the sample snapshot below).
$fixtureRawMap = @{
    Sensitivity_Labels       = Read-PpaFixture 'Samples\sample-raw\labels.json'
    Data_Loss_Prevention     = Read-PpaFixture 'Samples\sample-raw\dlp.json'
    Retention                = Read-PpaFixture 'Samples\sample-raw\retention.json'
    Insider_Risk             = Read-PpaFixture 'Samples\sample-raw\insiderrisk.json'
    Audit                    = Read-PpaFixture 'Samples\sample-raw\audit.json'
    eDiscovery               = Read-PpaFixture 'Samples\sample-raw\ediscovery.json'
    Communication_Compliance = Read-PpaFixture 'Samples\sample-raw\commscompliance.json'
    DSPM_for_AI              = Read-PpaFixture 'Samples\sample-raw\dspm.json'
}
$denseCoverage = Get-PpaCoverageModel -RawMap $fixtureRawMap
$dense = Read-PpaFixture 'Samples\sample-normalized-dense.json'
$denseNorm = ConvertTo-PpaNormalized -Meta $dense.meta -Licensing $dense.licensing -Sections $dense.sections -Observations $dense.observations -Coverage $denseCoverage
Write-PpaSampleReport -Name 'sample-dense.html' -Html (Export-PpaHtmlReport -Normalized $denseNorm -IsSample)

# ---- 3. Sparse fixture (raw sparse JSON through the real analyzers - graceful absence) ----
$licMap = Get-PpaLicenseRequirements -Path (Join-Path $root 'Data\license-requirements.json')
$sparseSections = @(
    Invoke-PpaLabelAnalyzer -Raw (Read-PpaFixture 'Samples\sample-raw\sparse\labels-sparse.json') -AsOf ([datetime]'2026-07-01')
    Invoke-PpaDlpAnalyzer -Raw (Read-PpaFixture 'Samples\sample-raw\sparse\dlp-sparse.json') -AsOf ([datetime]'2026-07-01') -LicenseMap $licMap
    Invoke-PpaRetentionAnalyzer -Raw (Read-PpaFixture 'Samples\sample-raw\sparse\retention-sparse.json')
)
$sparseMeta = [pscustomobject]@{
    reportTitle  = 'PurviewPostureAnalyzer (PPA)'
    version      = '2.0'
    versionDate  = 'June 2026'
    dateDisplay  = '01-Jul-2026 10:15 UTC'
    organization = 'Fabrikam Robotics (sparse fixture)'
    tenant       = 'fabrikamrobotics.onmicrosoft.com'
    operator     = 'taylor.ng@fabrikamrobotics.com (Compliance Reader)'
    mode         = 'Read-only - configuration metadata only'
}
$sparseLic  = [pscustomobject]@{ note = [string]$std.licensing.note }
# Sparse matrix: only three collectors present - the graceful-absence case.
$sparseCoverage = Get-PpaCoverageModel -RawMap @{
    Sensitivity_Labels   = Read-PpaFixture 'Samples\sample-raw\sparse\labels-sparse.json'
    Data_Loss_Prevention = Read-PpaFixture 'Samples\sample-raw\sparse\dlp-sparse.json'
    Retention            = Read-PpaFixture 'Samples\sample-raw\sparse\retention-sparse.json'
}
$sparseNorm = ConvertTo-PpaNormalized -Meta $sparseMeta -Licensing $sparseLic -Sections $sparseSections -Coverage $sparseCoverage
Write-PpaSampleReport -Name 'sample-sparse.html' -Html (Export-PpaHtmlReport -Normalized $sparseNorm -IsSample)

# ---- 3b. Auto-labeling condition cases (Wave 5 cleanup Part 2) ----
# One policy per condition state - flat / grouped / unparsed / none / rules-unreadable -
# so the four contract outcomes are eyeballed side by side in a single LABELS-03 table.
# Kept out of the dense fixture on purpose (extending it would churn the golden snapshot).
$alSections = @(
    Invoke-PpaLabelAnalyzer -Raw (Read-PpaFixture 'Samples\sample-raw\labels-autolabel-cases.json') -AsOf ([datetime]'2026-07-01') -LicenseMap $licMap
)
$alMeta = [pscustomobject]@{
    reportTitle  = 'PurviewPostureAnalyzer (PPA)'
    version      = '2.0'
    versionDate  = 'June 2026'
    dateDisplay  = '01-Jul-2026 10:15 UTC'
    organization = 'Northwind Traders (auto-label conditions fixture)'
    tenant       = 'northwindtraders.onmicrosoft.com'
    operator     = 'sam.rivera@northwindtraders.com (Compliance Reader)'
    mode         = 'Read-only - configuration metadata only'
}
$alNorm = ConvertTo-PpaNormalized -Meta $alMeta -Licensing ([pscustomobject]@{ note = [string]$std.licensing.note }) -Sections $alSections
Write-PpaSampleReport -Name 'sample-autolabel-cases.html' -Html (Export-PpaHtmlReport -Normalized $alNorm -IsSample)

# ---- 3c. Degraded-run fixture (F-001): some collectors could not be read this run ----
# The whole point of F-001, made visible in one report: the not-readable sections
# (Labels/DLP/eDiscovery here) read "not readable this session" (Verify manually), NOT a
# fabricated "0 / Improvement / Recommendation", while a genuinely-empty-but-READABLE
# section (Retention) still reads "Improvement/Informational". The contrast is the point.
$degRawMap = [ordered]@{
    Sensitivity_Labels   = Read-PpaFixture 'Samples\sample-raw\degraded\labels-notreadable.json'
    Data_Loss_Prevention = Read-PpaFixture 'Samples\sample-raw\degraded\dlp-notreadable.json'
    Retention            = Read-PpaFixture 'Samples\sample-raw\degraded\retention-empty.json'
    eDiscovery           = Read-PpaFixture 'Samples\sample-raw\degraded\ediscovery-notreadable.json'
}
$degSections = @(
    Invoke-PpaLabelAnalyzer     -Raw $degRawMap.Sensitivity_Labels   -AsOf ([datetime]'2026-07-01') -LicenseMap $licMap
    Invoke-PpaDlpAnalyzer       -Raw $degRawMap.Data_Loss_Prevention -AsOf ([datetime]'2026-07-01') -LicenseMap $licMap
    Invoke-PpaRetentionAnalyzer -Raw $degRawMap.Retention            -LicenseMap $licMap
    Invoke-PpaEdiscoveryAnalyzer -Raw $degRawMap.eDiscovery          -LicenseMap $licMap
)
$degMeta = [pscustomobject]@{
    reportTitle  = 'PurviewPostureAnalyzer (PPA)'
    version      = '2.0'
    versionDate  = 'June 2026'
    dateDisplay  = '01-Jul-2026 10:15 UTC'
    organization = 'Tailspin Toys (degraded-run fixture)'
    tenant       = 'tailspintoys.onmicrosoft.com'
    operator     = 'jordan.lee@tailspintoys.com (partial roles)'
    mode         = 'Read-only - configuration metadata only'
}
$degCoverage = Get-PpaCoverageModel -RawMap $degRawMap
$degNorm = ConvertTo-PpaNormalized -Meta $degMeta -Licensing ([pscustomobject]@{ note = [string]$std.licensing.note }) -Sections $degSections -Coverage $degCoverage

# The degraded-run warning is emitted by the orchestrator on a live run (this build
# assembles from fixtures, so it is reproduced here from the collector outcomes - the same
# outcome set Invoke-PurviewPostureAnalyzer warns on - so the behavior is visible for the sample).
$degradedOutcomes = @('AccessDenied', 'CmdletUnavailable', 'Failed', 'Partial')
$degDegraded = @($degSections | Where-Object {
    $sid = [string]$_.id
    $degRawMap.Contains($sid) -and $null -ne $degRawMap[$sid] -and ($degradedOutcomes -contains [string]$degRawMap[$sid].outcome)
})
if ($degDegraded.Count -gt 0) {
    Write-Warning ("[degraded sample] {0} section(s) degraded - a read did not fully succeed: {1}. Affected findings read 'Verify manually'." -f $degDegraded.Count, ((@($degDegraded).title) -join ', '))
}
Write-PpaSampleReport -Name 'sample-degraded.html' -Html (Export-PpaHtmlReport -Normalized $degNorm -IsSample)

# ---- 4. Redacted variant (dense fixture, -Redact -RedactNames: strictest masking) ----
Write-PpaSampleReport -Name 'sample-dense-redacted.html' -Html (Export-PpaHtmlReport -Normalized $denseNorm -IsSample -Redact -RedactNames)

# ---- 5. Profile-filtered variant (dense fixture minus DSPM for AI + Audit) ----
$sel = Select-PpaSections -Sections @($dense.sections) -ExcludeSection @('DSPM_for_AI', 'Audit')
$profNorm = ConvertTo-PpaNormalized -Meta $dense.meta -Licensing $dense.licensing -Sections $sel.Sections -Observations $dense.observations -Coverage $denseCoverage
Write-PpaSampleReport -Name 'sample-dense-profile.html' -Html (Export-PpaHtmlReport -Normalized $profNorm -IsSample -ExcludedSections $sel.ExcludedTitles)

# ---- 6. Dense snapshot sample (Wave 4 Part B: raw fixtures -> analyzers -> snapshot) ----
# FIXTURE TENANT ID: sample snapshots have no session, so the tenantId is this
# constant - a fixture token, not a real tenant. Snapshot filenames derive their
# tenantIdShort ('contosod') from it. Tests use the same value (Snapshot.Tests.ps1).
$fixtureTenantId = 'contoso-dense-fixture'
$snapRawMap = $fixtureRawMap
$snapAsOf = [datetime]'2026-06-24'
$snapSections = @(
    Invoke-PpaLabelAnalyzer -Raw $snapRawMap.Sensitivity_Labels -AsOf $snapAsOf -LicenseMap $licMap
    Invoke-PpaDlpAnalyzer -Raw $snapRawMap.Data_Loss_Prevention -AsOf $snapAsOf -LicenseMap $licMap
    Invoke-PpaRetentionAnalyzer -Raw $snapRawMap.Retention -LicenseMap $licMap
    Invoke-PpaInsiderRiskAnalyzer -Raw $snapRawMap.Insider_Risk -LicenseMap $licMap
    Invoke-PpaAuditAnalyzer -Raw $snapRawMap.Audit -LicenseMap $licMap
    Invoke-PpaEdiscoveryAnalyzer -Raw $snapRawMap.eDiscovery -LicenseMap $licMap
    Invoke-PpaCommsComplianceAnalyzer -Raw $snapRawMap.Communication_Compliance -LicenseMap $licMap
    Invoke-PpaDspmAiAnalyzer -Raw $snapRawMap.DSPM_for_AI -LicenseMap $licMap -HasSiteLabels:$false
)
$snapModel = New-PpaSnapshotModel `
    -RawMap $snapRawMap -Sections $snapSections `
    -Meta ([pscustomobject]@{ version = '2.0'; tenantId = $fixtureTenantId }) `
    -CapturedAt ([datetime]::new(2026, 7, 3, 14, 15, 0, [System.DateTimeKind]::Utc)) `
    -SnapshotId ([guid]::NewGuid().ToString())
$snapResult = Export-PpaSnapshot -Model $snapModel -Directory $OutDir
$written.Add($snapResult.SnapshotPath)

# ---- 7. Delta report samples (Wave 4 Part C): the torture pair (validation) and
# the showcase pair (presentable, degradation-free - C-fix 7). PS 7.5+ only, like
# delta mode itself; skipped silently under 5.1 so writer-side samples still build.
if (Test-PpaDeltaEngine) {
    foreach ($pair in @('dense-delta', 'showcase-delta')) {
        $deltaResult = Invoke-PpaDelta `
            -FromPath (Join-Path $root "Samples\delta-fixtures\$pair-A.json") `
            -ToPath (Join-Path $root "Samples\delta-fixtures\$pair-B.json") `
            -OutputPath $OutDir -WarningAction SilentlyContinue
        $written.Add($deltaResult.DeltaPath)
    }
}
else {
    Write-Host 'Delta report samples skipped: requires PowerShell 7.5+ (delta mode engine gate).'
}

# ---- Done ----
Write-Host ''
Write-Host 'Sample reports written:'
foreach ($p in $written) { Write-Host "  $p" }
