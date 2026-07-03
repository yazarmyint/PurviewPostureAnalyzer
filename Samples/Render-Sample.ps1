# Render-Sample.ps1 - render the sample fixture to HTML + JSON for side-by-side review
# against posture-report-mock-v5.html. Phase-1/2 preview harness (no tenant needed).
# Exercises the real assemble -> render/export pipeline:
#   sample-normalized.json -> ConvertTo-PpaNormalized -> Export-PpaHtmlReport / Export-PpaJson
#
#   pwsh -File Samples/Render-Sample.ps1
#
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path $PSScriptRoot 'sample-output')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

. (Join-Path $root 'Private\Model\PpaStatus.ps1')
. (Join-Path $root 'Private\Model\New-PpaFinding.ps1')
. (Join-Path $root 'Private\Model\ConvertTo-PpaNormalized.ps1')
. (Join-Path $root 'Private\Render\PpaHtml.ps1')
. (Join-Path $root 'Private\Render\Export-PpaHtmlReport.ps1')
. (Join-Path $root 'Private\Render\Export-PpaJson.ps1')

$jsonPath = Join-Path $PSScriptRoot 'sample-normalized.json'
$raw = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

# Assemble the canonical normalized object (counts + glance computed here).
$normalized = ConvertTo-PpaNormalized -Meta $raw.meta -Licensing $raw.licensing -Sections $raw.sections -Observations $raw.observations

if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$htmlPath = Join-Path $OutDir 'posture-report.html'
$jsonOut  = Join-Path $OutDir 'posture-report.json'

$html = Export-PpaHtmlReport -Normalized $normalized -IsSample
[System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding($false)))
[void](Export-PpaJson -Normalized $normalized -Path $jsonOut)

Write-Host "Rendered sample report -> $htmlPath"
Write-Host "Exported JSON          -> $jsonOut"
