# Build-PublishPackage.ps1 - stage the publishable module tree via a strict allowlist copy.
# F-013 Part A: the staging folder is the single enforced source of truth for what ships;
# there is deliberately NO manifest FileList (drift-prone duplicate metadata that does not
# actually filter the package).
#
# Copies ONLY, preserving top-level structure exactly:
#   Files   : PurviewPostureAnalyzer.psd1, PurviewPostureAnalyzer.psm1, LICENSE, NOTICE
#   Folders : Public\, Private\, Data\ (whole subtrees)
# Everything else stays behind by construction (allowlist), including: archive\, docs\,
# Image\, Outputs\, Samples\, Tests\, tools\ and root dev files (.gitignore,
# CHECK_CATALOG.md, CODE_OF_CONDUCT.md, CONTRIBUTING.md, PLAN.md, README.md,
# LIMITATIONS.md, SECURITY.md, SUPPORT.md).
#
# Final layout: <stage-root>\PurviewPostureAnalyzer\<module files> - the publish step
# points at that module-named folder. The stage root is recreated clean on every run.
#
#   pwsh -File tools/Build-PublishPackage.ps1
#   powershell.exe -File tools\Build-PublishPackage.ps1
#
# ASCII-only source (Windows PowerShell 5.1).
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$StageRoot
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StageRoot)) { $StageRoot = Join-Path $env:TEMP 'PPA-Publish-Stage' }

$allowFiles   = @('PurviewPostureAnalyzer.psd1', 'PurviewPostureAnalyzer.psm1', 'LICENSE', 'NOTICE')
$allowFolders = @('Public', 'Private', 'Data')

# ---- Preflight: every allowlisted source must exist before we touch the destination ----
foreach ($name in $allowFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)) {
        throw "Allowlisted file missing from repo root: $name"
    }
}
foreach ($name in $allowFolders) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $name) -PathType Container)) {
        throw "Allowlisted folder missing from repo root: $name"
    }
}

# ---- Safety rails on the stage root: must be outside the repo, never a drive root ----
$repoFull  = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
$stageFull = [System.IO.Path]::GetFullPath($StageRoot).TrimEnd('\')
if ($stageFull -match '^[A-Za-z]:$') {
    throw "Refusing to use a drive root as the stage root: $StageRoot"
}
$stageIsRepo   = [string]::Equals($stageFull, $repoFull, [System.StringComparison]::OrdinalIgnoreCase)
$stageInRepo   = $stageFull.StartsWith($repoFull + '\', [System.StringComparison]::OrdinalIgnoreCase)
if ($stageIsRepo -or $stageInRepo) {
    throw "Stage root must be OUTSIDE the repo. Repo: $repoFull  Requested: $stageFull"
}

# ---- Clean rebuild: remove any previous stage so every build starts empty ----
if (Test-Path -LiteralPath $stageFull) {
    Remove-Item -LiteralPath $stageFull -Recurse -Force -Confirm:$false
}
$moduleDir = Join-Path $stageFull 'PurviewPostureAnalyzer'
New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null

# ---- Allowlist copy, preserving structure ----
foreach ($name in $allowFiles) {
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $moduleDir $name)
}
foreach ($name in $allowFolders) {
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $moduleDir $name) -Recurse
}

# ---- Print exactly what landed so the operator can eyeball it ----
Write-Host ''
Write-Host "Staged module folder: $moduleDir"
Write-Host ''
Write-Host 'PurviewPostureAnalyzer\'
$entries = Get-ChildItem -LiteralPath $moduleDir -Recurse -Force | Sort-Object FullName
foreach ($entry in $entries) {
    $rel = $entry.FullName.Substring($moduleDir.Length + 1)
    $depth = ([regex]::Matches($rel, '\\')).Count
    $indent = '  ' * ($depth + 1)
    if ($entry.PSIsContainer) {
        Write-Host ("{0}{1}\" -f $indent, $entry.Name)
    } else {
        Write-Host ("{0}{1}" -f $indent, $entry.Name)
    }
}

$files = @($entries | Where-Object { -not $_.PSIsContainer })
$dirs  = @($entries | Where-Object { $_.PSIsContainer })
$bytes = ($files | Measure-Object -Property Length -Sum).Sum
if ($null -eq $bytes) { $bytes = 0 }
Write-Host ''
Write-Host ("Summary: {0} file(s), {1} folder(s), {2:N0} bytes." -f $files.Count, $dirs.Count, $bytes)

# Top-level must be exactly the allowlist - fail loudly if anything else appears.
$expectedTop = @($allowFiles + $allowFolders | Sort-Object)
$actualTop   = @(Get-ChildItem -LiteralPath $moduleDir -Force | Sort-Object Name | ForEach-Object { $_.Name })
$diff = Compare-Object -ReferenceObject $expectedTop -DifferenceObject $actualTop
if ($null -ne $diff) {
    $names = ($diff | ForEach-Object { $_.InputObject }) -join ', '
    throw "Staged top level does not match the allowlist. Unexpected/missing: $names"
}
Write-Host 'Top-level contents match the allowlist exactly.'
