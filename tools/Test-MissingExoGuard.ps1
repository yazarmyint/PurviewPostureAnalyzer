# Test-MissingExoGuard.ps1 - F-014 Part C: operator-run TEST-box check of the
# ExchangeOnlineManagement presence guard, credential-free.
#
# What it does:
#   PHASE 1 (sealed room): makes ExchangeOnlineManagement UNDISCOVERABLE for this
#   process only, by dropping every PSModulePath directory that contains it
#   (nothing is uninstalled; $env:PSModulePath is restored in a finally). It then
#   drives the three REAL entry paths to the guard and asserts each stops with a
#   terminating error whose message equals the guard's locked text EXACTLY
#   (case-sensitive):
#     1. Connect-PurviewPostureSession                      (direct/manual path)
#     2. Invoke-PurviewPostureAnalyzer -Connect             (one-go switch path)
#     3. Connect-PurviewPostureSession -DelegatedOrganization ... (guest/B2B path)
#   In the sealed room the two auth cmdlets (Connect-IPPSSession /
#   Connect-ExchangeOnline) do not even resolve - asserted explicitly - so an
#   auth prompt is structurally impossible; the guard message proves the stop
#   happened AT THE GUARD, before any connection work.
#
#   PHASE 2 (counter-case): with EXO discoverable again (PSModulePath restored),
#   asserts the guard does NOT fire. Module autoloading is suspended and two
#   session-local recording stubs stand in for the auth cmdlets, so the REAL
#   chokepoint runs end to end - real availability check, real code path - and
#   stops short of a real connection (no prompt, no tenant). Stubs and the
#   autoload preference are removed/restored in a finally.
#
# Run it on the TEST box (EXO installed), from a FRESH console with no
# ExchangeOnlineManagement imported and no live tenant session:
#
#   powershell.exe -NoProfile -File tools\Test-MissingExoGuard.ps1
#   pwsh -NoProfile -File tools/Test-MissingExoGuard.ps1
#
# Exit codes: 0 = all assertions passed; 1 = one or more failed; 2 = precondition
# stop (nothing was changed). ASCII-only source (Windows PowerShell 5.1).
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ModuleManifest
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModuleManifest)) { $ModuleManifest = Join-Path $repoRoot 'PurviewPostureAnalyzer.psd1' }

# ---- Assertion plumbing ----
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

# The guard's locked message, composed at runtime exactly as the source composes it.
$expectedGuardMessage = @(
    'ExchangeOnlineManagement module not found.'
    'PurviewPostureAnalyzer needs it to connect to Microsoft Purview. PPA stopped before connecting.'
    ''
    'To install it, run:'
    ('    ' + 'Install' + '-Module ExchangeOnlineManagement -Scope CurrentUser')
    ''
    'Then run PurviewPostureAnalyzer again.'
) -join [Environment]::NewLine

Write-Host ('Engine            : PowerShell ' + $PSVersionTable.PSVersion.ToString())
Write-Host ('Module manifest   : ' + $ModuleManifest)

# ---- Preconditions (nothing has been changed yet) ----
if (-not (Test-Path -LiteralPath $ModuleManifest -PathType Leaf)) {
    Write-Host "STOP: module manifest not found: $ModuleManifest"
    exit 2
}
if (Get-Module -Name ExchangeOnlineManagement) {
    Write-Host 'STOP: ExchangeOnlineManagement is IMPORTED in this session. The sealed room'
    Write-Host 'cannot be established without disturbing your session (and possibly a live'
    Write-Host 'tenant connection), which this helper refuses to do. Run it again from a'
    Write-Host 'FRESH console with no EXO module imported and no live session.'
    exit 2
}
$exoOnDiskAtStart = (@(Get-Module -ListAvailable -Name ExchangeOnlineManagement).Count -gt 0)
Write-Host ('EXO discoverable  : ' + $exoOnDiskAtStart)
if (-not $exoOnDiskAtStart) {
    Write-Host 'NOTE: ExchangeOnlineManagement is not discoverable on this box at all, so the'
    Write-Host 'absence paths below exercise REAL absence (no sealing needed) but the PHASE 2'
    Write-Host 'counter-case cannot run here. For the full check, run on the TEST box with'
    Write-Host 'EXO installed.'
}

$ppaWasLoaded = [bool](Get-Module -Name PurviewPostureAnalyzer)
Import-Module $ModuleManifest -Force
Write-Host ''

# =====================================================================
# PHASE 1 - sealed room: EXO undiscoverable, drive all three real paths
# =====================================================================
Write-Host '---- PHASE 1: sealed room (EXO undiscoverable) ----'
$origPSModulePath = $env:PSModulePath
$cwdDir = Join-Path $env:TEMP 'PPA-GuardCheck-CWD'
$pushed = $false
try {
    # Drop every PSModulePath directory that contains ExchangeOnlineManagement.
    $kept = @()
    $dropped = @()
    foreach ($dir in @($origPSModulePath -split ';')) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        $hasExo = $false
        try { $hasExo = Test-Path -LiteralPath (Join-Path $dir 'ExchangeOnlineManagement') } catch { $hasExo = $false }
        if ($hasExo) { $dropped += $dir } else { $kept += $dir }
    }
    $env:PSModulePath = ($kept -join ';')
    foreach ($dir in $dropped) { Write-Host ('  sealed out: ' + $dir) }

    Assert-Ppa -Name 'sealed room: EXO no longer discoverable' -Condition (@(Get-Module -ListAvailable -Name ExchangeOnlineManagement).Count -eq 0)
    $ippsCmd = Get-Command -Name 'Connect-IPPSSession' -ErrorAction SilentlyContinue
    $exoCmd  = Get-Command -Name 'Connect-ExchangeOnline' -ErrorAction SilentlyContinue
    Assert-Ppa -Name 'sealed room: neither auth cmdlet resolves (auth prompt structurally impossible)' -Condition (($null -eq $ippsCmd) -and ($null -eq $exoCmd))

    # -- Path 1: direct Connect-PurviewPostureSession --
    $err1 = $null
    try { $null = Connect-PurviewPostureSession } catch { $err1 = $_ }
    Assert-Ppa -Name 'path 1 (direct connect): terminating stop' -Condition ($null -ne $err1)
    Assert-Ppa -Name 'path 1 (direct connect): message equals locked text (case-sensitive)' -Condition (($null -ne $err1) -and ($err1.Exception.Message -ceq $expectedGuardMessage))

    # -- Path 2: Invoke-PurviewPostureAnalyzer -Connect (run from a temp CWD so the
    #    pre-guard OutputDirectory resolution can never touch the repo; nothing is
    #    written before the guard fires - the run manifest init is in-memory). --
    if (-not (Test-Path -LiteralPath $cwdDir)) { New-Item -ItemType Directory -Path $cwdDir -Force | Out-Null }
    Push-Location -LiteralPath $cwdDir
    $pushed = $true
    $err2 = $null
    try { $null = Invoke-PurviewPostureAnalyzer -Organization 'Guard Check' -Connect } catch { $err2 = $_ }
    Pop-Location
    $pushed = $false
    Assert-Ppa -Name 'path 2 (-Connect switch): terminating stop' -Condition ($null -ne $err2)
    Assert-Ppa -Name 'path 2 (-Connect switch): message equals locked text (case-sensitive)' -Condition (($null -ne $err2) -and ($err2.Exception.Message -ceq $expectedGuardMessage))

    # -- Path 3: guest/B2B via -DelegatedOrganization --
    $err3 = $null
    try { $null = Connect-PurviewPostureSession -DelegatedOrganization 'sealed-room-client.onmicrosoft.com' } catch { $err3 = $_ }
    Assert-Ppa -Name 'path 3 (guest/B2B): terminating stop' -Condition ($null -ne $err3)
    Assert-Ppa -Name 'path 3 (guest/B2B): message equals locked text (case-sensitive)' -Condition (($null -ne $err3) -and ($err3.Exception.Message -ceq $expectedGuardMessage))
}
finally {
    if ($pushed) { Pop-Location }
    $env:PSModulePath = $origPSModulePath
    if (Test-Path -LiteralPath $cwdDir) {
        try { Remove-Item -LiteralPath $cwdDir -Recurse -Force -Confirm:$false } catch { Write-Host ('Cleanup warning: could not delete temp CWD: ' + $_.Exception.Message) }
    }
}
Assert-Ppa -Name 'cleanup: PSModulePath restored' -Condition ($env:PSModulePath -eq $origPSModulePath)
Write-Host ''

# =====================================================================
# PHASE 2 - counter-case: EXO discoverable, the guard must NOT fire
# =====================================================================
Write-Host '---- PHASE 2: counter-case (EXO discoverable, guard silent) ----'
if (-not $exoOnDiskAtStart) {
    Assert-Ppa -Name 'counter-case: EXO discoverable on this box' -Condition $false -Detail 'BLOCKED - ExchangeOnlineManagement is not installed here; run on the TEST box for the full check'
} else {
    $autoVar = Get-Variable -Name PSModuleAutoloadingPreference -Scope Global -ErrorAction SilentlyContinue
    $autoExisted = ($null -ne $autoVar)
    $autoPrev = $null
    if ($autoExisted) { $autoPrev = $autoVar.Value }
    try {
        # Suspend module autoloading so Get-Command/name resolution cannot import the
        # real EXO module behind our backs, then interpose recording stubs. The guard's
        # availability check still sees the REAL on-disk module (ListAvailable reads
        # disk, not the autoloader), so the chokepoint runs its genuine code path and
        # stops short of a real connection at the stubs. No credentials, no prompt.
        $global:PSModuleAutoloadingPreference = 'None'
        $global:PpaGuardCheckIppsCalled = $false
        $global:PpaGuardCheckExoCalled  = $false
        function global:Connect-IPPSSession {
            [CmdletBinding()]
            param([string]$UserPrincipalName, [string]$DelegatedOrganization, [string]$AzureADAuthorizationEndpointUri, [bool]$ShowBanner)
            $global:PpaGuardCheckIppsCalled = $true
        }
        function global:Connect-ExchangeOnline {
            [CmdletBinding()]
            param([string]$UserPrincipalName, [string]$DelegatedOrganization, [string]$AzureADAuthorizationEndpointUri, [bool]$ShowBanner)
            $global:PpaGuardCheckExoCalled = $true
        }

        $ppaModule = Get-Module -Name PurviewPostureAnalyzer | Select-Object -First 1
        $probe = & $ppaModule { Test-PpaExoModuleAvailable }
        Assert-Ppa -Name 'counter-case: guard predicate sees EXO as available' -Condition ($probe -eq $true)

        $errC = $null
        $rC = $null
        try { $rC = Connect-PurviewPostureSession } catch { $errC = $_ }
        Assert-Ppa -Name 'counter-case: no terminating error from the guard' -Condition ($null -eq $errC) -Detail $(if ($errC) { $errC.Exception.Message } else { '' })
        $bothConnected = $false
        if ($null -ne $rC) { $bothConnected = (([string]$rC.SecurityCompliance -eq 'connected') -and ([string]$rC.ExchangeOnline -eq 'connected')) }
        Assert-Ppa -Name 'counter-case: chokepoint proceeded past the guard (both services reached the stubs)' -Condition ($bothConnected -and $global:PpaGuardCheckIppsCalled -and $global:PpaGuardCheckExoCalled)
        Assert-Ppa -Name 'counter-case: real EXO module was never imported (no session disturbance)' -Condition ($null -eq (Get-Module -Name ExchangeOnlineManagement))
    }
    finally {
        foreach ($fn in @('Connect-IPPSSession', 'Connect-ExchangeOnline')) {
            if (Test-Path "function:global:$fn") { Remove-Item "function:global:$fn" -Force -ErrorAction SilentlyContinue }
        }
        Remove-Variable -Name PpaGuardCheckIppsCalled -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name PpaGuardCheckExoCalled -Scope Global -ErrorAction SilentlyContinue
        if ($autoExisted) { $global:PSModuleAutoloadingPreference = $autoPrev }
        else { Remove-Variable -Name PSModuleAutoloadingPreference -Scope Global -ErrorAction SilentlyContinue }
    }
    $stubsGone = ((-not (Test-Path 'function:global:Connect-IPPSSession')) -and (-not (Test-Path 'function:global:Connect-ExchangeOnline')))
    Assert-Ppa -Name 'cleanup: recording stubs removed' -Condition $stubsGone
}

# ---- Final module-state restore: only unload PPA if this helper loaded it ----
if (-not $ppaWasLoaded) {
    Remove-Module -Name PurviewPostureAnalyzer -Force -ErrorAction SilentlyContinue
    Write-Host 'Cleanup: PurviewPostureAnalyzer unloaded (it was not imported before this run).'
} else {
    Write-Host 'Note: PurviewPostureAnalyzer was already imported before this run; it stays imported (re-imported -Force from the manifest above).'
}

Write-Host ''
if ($script:Failures.Count -eq 0) {
    Write-Host 'MISSING-EXO GUARD CHECK: ALL ASSERTIONS PASSED.'
    exit 0
} else {
    Write-Host ('MISSING-EXO GUARD CHECK: {0} FAILURE(S): {1}' -f $script:Failures.Count, ($script:Failures -join '; '))
    exit 1
}
