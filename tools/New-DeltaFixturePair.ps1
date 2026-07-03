# New-DeltaFixturePair.ps1 - derives the checked-in delta fixture snapshots A and B
# from the dense fixture using the EXPLICIT mutation table (Wave 4 spec 6.1,
# tools/delta-fixture-mutations.json). Fully deterministic: fixed snapshot ids,
# fixed capture times, injected environment - regenerating must deep-compare equal
# to the checked-in pair (drift guard test in Tests/Delta.Tests.ps1).
#
#   pwsh -File tools/New-DeltaFixturePair.ps1 [-OutDir <dir>]
#
# ASCII-only source.
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $root 'Samples\delta-fixtures' }
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

foreach ($file in (Get-ChildItem -Path (Join-Path $root 'Private') -Recurse -Filter '*.ps1')) { . $file.FullName }

# Parse preserving date-like strings verbatim (PS 7.5+ -DateKind String; 5.1
# never converts) so fixture fidelity never depends on DateTime round-tripping.
$script:ParseArgs = @{}
if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $script:ParseArgs['DateKind'] = 'String' }

function Read-PpaFixture([string]$RelPath) {
    ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText((Join-Path $root $RelPath), [System.Text.Encoding]::UTF8)) @script:ParseArgs
}

# ---- base snapshot model: the dense fixture through the real writer ----
$rawMap = @{
    Sensitivity_Labels       = Read-PpaFixture 'Samples\sample-raw\labels.json'
    Data_Loss_Prevention     = Read-PpaFixture 'Samples\sample-raw\dlp.json'
    Retention                = Read-PpaFixture 'Samples\sample-raw\retention.json'
    Insider_Risk             = Read-PpaFixture 'Samples\sample-raw\insiderrisk.json'
    Audit                    = Read-PpaFixture 'Samples\sample-raw\audit.json'
    eDiscovery               = Read-PpaFixture 'Samples\sample-raw\ediscovery.json'
    Communication_Compliance = Read-PpaFixture 'Samples\sample-raw\commscompliance.json'
    DSPM_for_AI              = Read-PpaFixture 'Samples\sample-raw\dspm.json'
}
$licMap = Get-PpaLicenseRequirements -Path (Join-Path $root 'Data\license-requirements.json')
$sitMap = Read-PpaFixture 'Data\dlp-sit-tiers.json'
$asOf = [datetime]'2026-06-24'
$sections = @(
    Invoke-PpaLabelAnalyzer -Raw $rawMap.Sensitivity_Labels -AsOf $asOf -LicenseMap $licMap
    Invoke-PpaDlpAnalyzer -Raw $rawMap.Data_Loss_Prevention -AsOf $asOf -LicenseMap $licMap -SitTierMap $sitMap
    Invoke-PpaRetentionAnalyzer -Raw $rawMap.Retention -LicenseMap $licMap
    Invoke-PpaInsiderRiskAnalyzer -Raw $rawMap.Insider_Risk -LicenseMap $licMap
    Invoke-PpaAuditAnalyzer -Raw $rawMap.Audit -LicenseMap $licMap
    Invoke-PpaEdiscoveryAnalyzer -Raw $rawMap.eDiscovery -LicenseMap $licMap
    Invoke-PpaCommsComplianceAnalyzer -Raw $rawMap.Communication_Compliance -LicenseMap $licMap
    Invoke-PpaDspmAiAnalyzer -Raw $rawMap.DSPM_for_AI -LicenseMap $licMap -HasSiteLabels:$false
)
$baseModel = New-PpaSnapshotModel `
    -RawMap $rawMap -Sections $sections `
    -Meta ([pscustomobject]@{ version = '2.0'; tenantId = 'contoso-dense-fixture' }) `
    -CapturedAt ([datetime]::new(2026, 6, 24, 0, 0, 0, [System.DateTimeKind]::Utc)) `
    -SnapshotId '00000000-0000-0000-0000-000000000000' `
    -Environment ([ordered]@{ psEdition = 'Fixture'; psVersion = 'delta-fixture'; modules = [ordered]@{} })

# Two independent parsed copies to mutate (snapshot-level mutation, like a real
# pair of runs would differ).
$baseJson = ConvertTo-Json -InputObject $baseModel -Depth 16
$snapA = ConvertFrom-Json -InputObject $baseJson @script:ParseArgs
$snapB = ConvertFrom-Json -InputObject $baseJson @script:ParseArgs

$schema = Get-PpaSnapshotSchema
$table = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText((Join-Path $root 'tools\delta-fixture-mutations.json'), [System.Text.Encoding]::UTF8)) @script:ParseArgs

function Get-PpaMutationTarget {
    param($Snap, [string]$Type, [string]$Key)
    $hit = @($Snap.objects.$Type | Where-Object { [string]$_._key -eq $Key })
    if ($hit.Count -ne 1) { throw "Mutation target not found (or ambiguous): type '$Type' key '$Key'." }
    return $hit[0]
}

foreach ($op in @($table.ops)) {
    $snap = if ([string]$op.side -eq 'A') { $snapA } else { $snapB }
    switch ([string]$op.op) {
        'setMeta' {
            $snap.$($op.field) = $op.value
        }
        'addObject' {
            $snap.objects.$($op.type) = @($snap.objects.$($op.type)) + @($op.object)
        }
        'removeObject' {
            $snap.objects.$($op.type) = @($snap.objects.$($op.type) | Where-Object { [string]$_._key -ne [string]$op.key })
        }
        'setProperty' {
            $target = Get-PpaMutationTarget -Snap $snap -Type ([string]$op.type) -Key ([string]$op.key)
            if ($op.value -is [System.Array]) { $target.$($op.property) = @($op.value) }
            else { $target.$($op.property) = $op.value }
        }
        'injectProperty' {
            $target = Get-PpaMutationTarget -Snap $snap -Type ([string]$op.type) -Key ([string]$op.key)
            $target | Add-Member -NotePropertyName ([string]$op.property) -NotePropertyValue $op.value -Force
        }
        'setOutcome' {
            $snap.collectorOutcomes.$($op.section) = [string]$op.value
        }
        'clearType' {
            $snap.objects.$($op.type) = @()
        }
        'dropSection' {
            $sid = [string]$op.section
            $snap.sectionsRun = @($snap.sectionsRun | Where-Object { [string]$_ -ne $sid })
            $snap.collectorOutcomes.$sid = 'Skipped'
            foreach ($tp in $schema.types.PSObject.Properties) {
                if ([string]$tp.Value.section -eq $sid -and ($snap.objects.PSObject.Properties.Name -contains $tp.Name)) {
                    $snap.objects.PSObject.Properties.Remove($tp.Name)
                }
            }
            $snap.findings = @($snap.findings | Where-Object { [string]$_.section -ne $sid })
        }
        'setFindingStatus' {
            $hit = @($snap.findings | Where-Object { [string]$_.checkId -eq [string]$op.checkId })
            if ($hit.Count -ne 1) { throw "Finding not found (or ambiguous): '$($op.checkId)'." }
            $hit[0].status = [string]$op.value
        }
        default { throw "Unknown mutation op '$($op.op)'." }
    }
}

$pathA = Join-Path $OutDir 'dense-delta-A.json'
$pathB = Join-Path $OutDir 'dense-delta-B.json'
[System.IO.File]::WriteAllText($pathA, (ConvertTo-Json -InputObject $snapA -Depth 16), (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($pathB, (ConvertTo-Json -InputObject $snapB -Depth 16), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Delta fixture A : $pathA"
Write-Host "Delta fixture B : $pathB"
