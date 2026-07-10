# Test-PublishPackage.ps1 - F-013 Part B: local-repository dress rehearsal.
# Publishes the staged package (from Build-PublishPackage.ps1) to a TEMPORARY local
# filesystem PSRepository, saves it back out, imports it BY NAME, and asserts:
#   (a) the three public functions are exported and visible
#   (b) the Data JSONs physically landed under <saved-module-root>\Data\
#   (c) Data resolves at RUNTIME from the installed location, proven by invoking the
#       connection-free loaders (Get-PpaRemediationCatalog / Get-PpaLicenseRequirements)
#       in module scope; if those helpers are not found, falls back to (b) and marks
#       runtime resolution DEFERRED to the F-014 tenant run.
#
# There is NO real Gallery publish here and NO real API key anywhere in this script.
# The literal 'LOCAL' below is a throwaway placeholder for the filesystem repository
# (which uses no key at all); it is NOT the PowerShell Gallery key.
#
# Self-contained, repeatable, zero residue: cleanup runs in a finally block and the
# script verifies afterwards that PSModulePath, the session, the repository list and
# the temp folders are all back exactly as found.
#
#   pwsh -File tools/Test-PublishPackage.ps1
#     (requires PowerShellGet v2+ or Microsoft.PowerShell.PSResourceGet; the script
#      STOPS and reports if neither is available - it never installs anything)
#
# ASCII-only source (Windows PowerShell 5.1).
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$StagedModule,
    [string]$WorkRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StagedModule)) { $StagedModule = Join-Path $env:TEMP 'PPA-Publish-Stage\PurviewPostureAnalyzer' }
if ([string]::IsNullOrWhiteSpace($WorkRoot))     { $WorkRoot     = Join-Path $env:TEMP 'PPA-LocalDress' }

$moduleName = 'PurviewPostureAnalyzer'
$dressRepo  = 'PPA-LocalDress'
$feedDir    = Join-Path $WorkRoot 'feed'
$installDir = Join-Path $WorkRoot 'install'

# ---- Assertion plumbing: every check prints [PASS]/[FAIL] and failures are tallied ----
$script:Failures = New-Object System.Collections.Generic.List[string]
function Assert-Ppa {
    param([string]$Name, [bool]$Condition, [string]$Detail)
    if ($Condition) {
        Write-Host ("[PASS] {0}{1}" -f $Name, $(if ($Detail) { ' - ' + $Detail } else { '' }))
    } else {
        Write-Host ("[FAIL] {0}{1}" -f $Name, $(if ($Detail) { ' - ' + $Detail } else { '' }))
        $script:Failures.Add($Name)
    }
}

# ---- Input validation ----
if (-not (Test-Path -LiteralPath (Join-Path $StagedModule ($moduleName + '.psd1')) -PathType Leaf)) {
    Write-Host "Staged module not found at: $StagedModule"
    Write-Host 'Run tools\Build-PublishPackage.ps1 first (F-013 Part A), or pass -StagedModule.'
    exit 2
}

# ---- Safety rails on the work root: outside the repo, never a drive root ----
$repoFull = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\')
$workFull = [System.IO.Path]::GetFullPath($WorkRoot).TrimEnd('\')
if ($workFull -match '^[A-Za-z]:$') { throw "Refusing to use a drive root as the work root: $WorkRoot" }
$workIsRepo = [string]::Equals($workFull, $repoFull, [System.StringComparison]::OrdinalIgnoreCase)
$workInRepo = $workFull.StartsWith($repoFull + '\', [System.StringComparison]::OrdinalIgnoreCase)
if ($workIsRepo -or $workInRepo) { throw "Work root must be OUTSIDE the repo. Repo: $repoFull  Requested: $workFull" }

# ---- Preflight: pick a backend without installing anything ----
Write-Host ('Engine              : PowerShell ' + $PSVersionTable.PSVersion.ToString())
$psgV2 = Get-Module -ListAvailable PowerShellGet |
    Where-Object { $_.Version -ge [version]'2.0.0' } |
    Sort-Object Version -Descending | Select-Object -First 1
$prg = Get-Module -ListAvailable Microsoft.PowerShell.PSResourceGet |
    Sort-Object Version -Descending | Select-Object -First 1
$nuget = Get-PackageProvider -ListAvailable -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'NuGet' } | Select-Object -First 1
Write-Host ('PowerShellGet v2+   : ' + $(if ($psgV2) { $psgV2.Version.ToString() } else { 'not present' }))
Write-Host ('PSResourceGet       : ' + $(if ($prg)   { $prg.Version.ToString() }   else { 'not present' }))
Write-Host ('NuGet provider      : ' + $(if ($nuget) { $nuget.Version.ToString() } else { 'not present' }))

$backend = $null
if ($psgV2 -and $nuget) {
    $backend = 'PowerShellGetV2'
} elseif ($prg) {
    $backend = 'PSResourceGet'
}
if (-not $backend) {
    Write-Host ''
    Write-Host 'STOP: no usable publish backend on this engine. Needed (either one):'
    Write-Host '  - PowerShellGet 2.x plus the NuGet package provider (preferred), or'
    Write-Host '  - Microsoft.PowerShell.PSResourceGet.'
    Write-Host 'This script never installs components. Install one manually, or run under an'
    Write-Host 'engine that has one (pwsh 7 ships PowerShellGet 2.2.5 and PSResourceGet).'
    exit 2
}
Write-Host ('Backend selected    : ' + $backend)
Write-Host ('Staged module       : ' + $StagedModule)
Write-Host ('Feed folder         : ' + $feedDir)
Write-Host ('Install folder      : ' + $installDir)
Write-Host ''

# ---- State captured up front so the finally block can put everything back ----
$origPSModulePath = $env:PSModulePath
$repoRegistered   = $false

# Stale registration from an aborted earlier run? The name is distinctive, so it is ours.
if ($backend -eq 'PowerShellGetV2') {
    $stale = Get-PSRepository -Name $dressRepo -ErrorAction SilentlyContinue
    if ($stale) { Write-Host "Note: removing stale repository '$dressRepo' from an earlier run."; Unregister-PSRepository -Name $dressRepo }
} else {
    $stale = Get-PSResourceRepository -Name $dressRepo -ErrorAction SilentlyContinue
    if ($stale) { Write-Host "Note: removing stale repository '$dressRepo' from an earlier run."; Unregister-PSResourceRepository -Name $dressRepo }
}

try {
    # ---- Fresh temp dirs (feed + install), repo-external ----
    if (Test-Path -LiteralPath $WorkRoot) { Remove-Item -LiteralPath $WorkRoot -Recurse -Force -Confirm:$false }
    New-Item -ItemType Directory -Path $feedDir -Force | Out-Null
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null

    # ---- Register the temporary local repository (Trusted) ----
    if ($backend -eq 'PowerShellGetV2') {
        Register-PSRepository -Name $dressRepo -SourceLocation $feedDir -PublishLocation $feedDir -InstallationPolicy Trusted
    } else {
        Register-PSResourceRepository -Name $dressRepo -Uri $feedDir -Trusted
    }
    $repoRegistered = $true
    Write-Host "Registered temporary repository '$dressRepo' (Trusted, filesystem feed)."

    # ---- Publish the staged module to the local feed ----
    # 'LOCAL' is a throwaway literal for the filesystem repo, which uses no real key.
    # It is NOT the PowerShell Gallery API key; no real key appears anywhere in F-013.
    if ($backend -eq 'PowerShellGetV2') {
        Publish-Module -Path $StagedModule -Repository $dressRepo -NuGetApiKey 'LOCAL'
    } else {
        Publish-PSResource -Path $StagedModule -Repository $dressRepo
    }
    $nupkg = @(Get-ChildItem -LiteralPath $feedDir -Filter '*.nupkg')
    Assert-Ppa -Name 'Publish produced a package in the local feed' -Condition ($nupkg.Count -eq 1) -Detail $(if ($nupkg.Count -ge 1) { $nupkg[0].Name } else { 'no .nupkg found' })

    # ---- Save from the local repo into the temp install folder ----
    if ($backend -eq 'PowerShellGetV2') {
        Save-Module -Name $moduleName -Repository $dressRepo -Path $installDir
    } else {
        Save-PSResource -Name $moduleName -Repository $dressRepo -Path $installDir -TrustRepository
    }

    # ---- Import BY NAME via PSModulePath (this session only) ----
    $env:PSModulePath = $installDir + ';' + $origPSModulePath
    Import-Module $moduleName
    $mod = Get-Module -Name $moduleName
    Assert-Ppa -Name 'Module imported by name (no path)' -Condition ($null -ne $mod) -Detail $(if ($mod) { 'version ' + $mod.Version } else { 'Get-Module returned nothing' })
    $fromInstall = $false
    if ($mod) { $fromInstall = $mod.ModuleBase.StartsWith($installDir, [System.StringComparison]::OrdinalIgnoreCase) }
    Assert-Ppa -Name 'By-name resolution picked the saved copy' -Condition $fromInstall -Detail $(if ($mod) { $mod.ModuleBase } else { 'no module' })

    # ---- (a) The three public functions are exported and visible ----
    $expected = @('Connect-PurviewPostureSession', 'Disconnect-PurviewPostureSession', 'Invoke-PurviewPostureAnalyzer')
    $exported = @()
    if ($mod) { $exported = @($mod.ExportedFunctions.Keys) }
    foreach ($fn in $expected) {
        $visible = ($exported -contains $fn) -and ($null -ne (Get-Command -Name $fn -ErrorAction SilentlyContinue))
        Assert-Ppa -Name "(a) exported + visible: $fn" -Condition $visible
    }
    Assert-Ppa -Name '(a) exactly 3 functions exported' -Condition ($exported.Count -eq 3) -Detail ("exported: " + ($exported -join ', '))

    # ---- (b) Data JSONs physically landed under the saved module root ----
    $savedRoot = $null
    if ($mod) { $savedRoot = $mod.ModuleBase }
    foreach ($json in @('remediation-catalog.json', 'license-requirements.json')) {
        $p = $null
        if ($savedRoot) { $p = Join-Path (Join-Path $savedRoot 'Data') $json }
        $present = ($null -ne $p) -and (Test-Path -LiteralPath $p -PathType Leaf)
        Assert-Ppa -Name "(b) Data file present: Data\$json" -Condition $present -Detail $p
    }

    # ---- (c) Data runtime-resolution smoke check (ADAPTIVE) ----
    # Branch 1: connection-free loaders exist in module scope -> invoke them there and
    # assert real catalog content, proving Data\ resolves at runtime from the installed
    # location (the loaders default to a path built relative to the module root).
    # Branch 2: helpers absent -> rely on (b) and mark runtime resolution DEFERRED to
    # the F-014 tenant run. Never faked.
    $helperCmd = $null
    if ($mod) { $helperCmd = & $mod { Get-Command -Name 'Get-PpaRemediationCatalog' -ErrorAction SilentlyContinue } }
    if ($null -ne $helperCmd) {
        Write-Host '(c) branch: connection-free loader FOUND in module scope - proving runtime Data resolution.'
        $catalog = & $mod { Get-PpaRemediationCatalog }
        $catalogOk = $false
        $catalogDetail = 'loader returned null (Data path did not resolve)'
        if ($null -ne $catalog -and $null -ne $catalog.PSObject.Properties['checks'] -and $null -ne $catalog.checks) {
            $checkCount = @($catalog.checks.PSObject.Properties).Count
            $catalogOk = ($checkCount -gt 0)
            $catalogDetail = "$checkCount check entries loaded from installed Data\remediation-catalog.json"
        }
        Assert-Ppa -Name '(c) runtime load: Get-PpaRemediationCatalog' -Condition $catalogOk -Detail $catalogDetail

        $licOk = $false
        $licDetail = 'loader returned null or empty'
        $lic = & $mod { Get-PpaLicenseRequirements }
        if ($null -ne $lic) {
            $licCount = @($lic.PSObject.Properties).Count
            $licOk = ($licCount -gt 0)
            $licDetail = "$licCount properties loaded from installed Data\license-requirements.json"
        }
        Assert-Ppa -Name '(c) runtime load: Get-PpaLicenseRequirements' -Condition $licOk -Detail $licDetail
    } else {
        Write-Host '(c) branch: no connection-free loader found in module scope - falling back to (b).'
        Write-Host '(c) DEFERRED: full runtime Data resolution will be exercised in the F-014 TEST-box tenant run.'
    }
}
catch {
    Write-Host ('[ERROR] ' + $_.Exception.Message)
    $script:Failures.Add('unhandled error: ' + $_.Exception.Message)
}
finally {
    Write-Host ''
    Write-Host '---- Cleanup (always runs) ----'
    # 1. Drop the module from this session.
    Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
    # 2. Restore PSModulePath exactly as found.
    $env:PSModulePath = $origPSModulePath
    # 3. Unregister the temporary repository.
    if ($repoRegistered) {
        try {
            if ($backend -eq 'PowerShellGetV2') { Unregister-PSRepository -Name $dressRepo } else { Unregister-PSResourceRepository -Name $dressRepo }
        } catch {
            Write-Host ('Cleanup warning: could not unregister repository: ' + $_.Exception.Message)
        }
    }
    # 4. Delete both temp dirs (feed + install live under the one work root).
    try {
        if (Test-Path -LiteralPath $WorkRoot) { Remove-Item -LiteralPath $WorkRoot -Recurse -Force -Confirm:$false }
    } catch {
        Write-Host ('Cleanup warning: could not delete work root: ' + $_.Exception.Message)
    }

    # ---- Residue verification: the box must be exactly as found ----
    Assert-Ppa -Name 'cleanup: module removed from session' -Condition ($null -eq (Get-Module -Name $moduleName))
    Assert-Ppa -Name 'cleanup: PSModulePath restored' -Condition ($env:PSModulePath -eq $origPSModulePath)
    $repoGone = $true
    if ($backend -eq 'PowerShellGetV2') {
        if (Get-PSRepository -Name $dressRepo -ErrorAction SilentlyContinue) { $repoGone = $false }
    } else {
        if (Get-PSResourceRepository -Name $dressRepo -ErrorAction SilentlyContinue) { $repoGone = $false }
    }
    Assert-Ppa -Name "cleanup: repository '$dressRepo' unregistered" -Condition $repoGone
    Assert-Ppa -Name 'cleanup: temp dirs deleted' -Condition (-not (Test-Path -LiteralPath $WorkRoot)) -Detail $WorkRoot
}

Write-Host ''
if ($script:Failures.Count -eq 0) {
    Write-Host 'DRESS REHEARSAL: ALL ASSERTIONS PASSED, NO RESIDUE.'
    exit 0
} else {
    Write-Host ('DRESS REHEARSAL: {0} FAILURE(S): {1}' -f $script:Failures.Count, ($script:Failures -join '; '))
    exit 1
}
