# SessionSwitches.Tests.ps1 - UX-1: the opt-in one-go run switches on
# Invoke-PurviewPostureAnalyzer (-Connect / -Disconnect / -Show / -UserPrincipalName).
# The money test is the F-007 regression: a DEFAULT invocation calls NEITHER
# Connect-PurviewPostureSession NOR Disconnect-PurviewPostureSession - PPA never opens or
# tears down a session unless explicitly told to. Note on the finally proof: a COLLECTOR
# throw is swallowed by the honest-degradation catch (by design - the run completes
# degraded, covered by the completed-run case), so proving the finally uses a body-stage
# throw (run context) that actually fails the run. All session/process cmdlets are mocked
# at module scope; no real sign-in, teardown, or browser launch ever happens here.
# Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:RepoRoot 'PurviewPostureAnalyzer.psd1') -Force

    # Get-ConnectionInformation ships with ExchangeOnlineManagement, which is not
    # installed on the dev box. A global stub gives Pester a command to mock, and
    # deliberately shadows the real cmdlet on boxes that DO have it (deterministic).
    function global:Get-ConnectionInformation { [CmdletBinding()] param() @() }

    # Reusable fixture rows for the session probe.
    $script:SccRow = [pscustomobject]@{ State = 'Connected'; ConnectionUri = 'https://nam12.ps.compliance.protection.outlook.com'; UserPrincipalName = 'op@contoso.com' }
    $script:ExoRow = [pscustomobject]@{ State = 'Connected'; ConnectionUri = 'https://outlook.office365.com/powershell-liveid/'; UserPrincipalName = 'op@contoso.com' }
    $script:BothConnected = [pscustomobject]@{ SecurityCompliance = 'connected'; ExchangeOnline = 'connected' }
    $script:BothMissing   = [pscustomobject]@{ SecurityCompliance = 'ExchangeOnlineManagement module not installed'; ExchangeOnline = 'ExchangeOnlineManagement module not installed' }

    $script:OutRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ppa-switches-' + [guid]::NewGuid().ToString('N'))
}

AfterAll {
    if (Test-Path function:Get-ConnectionInformation) { Remove-Item function:Get-ConnectionInformation -Force -ErrorAction SilentlyContinue }
    if ($script:OutRoot -and (Test-Path -LiteralPath $script:OutRoot)) {
        Remove-Item -LiteralPath $script:OutRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module PurviewPostureAnalyzer -Force -ErrorAction SilentlyContinue
}

Describe 'UX-1 -Connect / -Disconnect defaults (F-007)' {
    It 'F-007 REGRESSION (the money test): a default invocation calls NEITHER Connect nor Disconnect' {
        Mock -ModuleName PurviewPostureAnalyzer Connect-PurviewPostureSession { }
        Mock -ModuleName PurviewPostureAnalyzer Disconnect-PurviewPostureSession { }
        $null = Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'default') -WarningAction SilentlyContinue
        Should -Invoke Connect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
        Should -Invoke Disconnect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
    }
}

Describe 'UX-1 -Connect' {
    It 'no live sessions: Connect is called exactly once, with the provided -UserPrincipalName' {
        Mock -ModuleName PurviewPostureAnalyzer Get-ConnectionInformation { @() }
        Mock -ModuleName PurviewPostureAnalyzer Connect-PurviewPostureSession { $script:BothConnected }
        $null = Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'connect-none') -Connect -UserPrincipalName 'op@contoso.com' -WarningAction SilentlyContinue
        Should -Invoke Connect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter { $UserPrincipalName -eq 'op@contoso.com' }
    }
    It 'one live session (SCC only): Connect is NOT called and the mixed-state warning fires' {
        Mock -ModuleName PurviewPostureAnalyzer Get-ConnectionInformation { $script:SccRow }
        Mock -ModuleName PurviewPostureAnalyzer Connect-PurviewPostureSession { $script:BothConnected }
        $null = Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'connect-mixed') -Connect -WarningVariable warns -WarningAction SilentlyContinue
        Should -Invoke Connect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
        @($warns | Where-Object { $_ -match 'skipping connect' -and $_ -match 'Connect-PurviewPostureSession yourself' }).Count | Should -Be 1
    }
    It 'both sessions live: Connect is NOT called and no mixed-state warning fires' {
        Mock -ModuleName PurviewPostureAnalyzer Get-ConnectionInformation { @($script:SccRow, $script:ExoRow) }
        Mock -ModuleName PurviewPostureAnalyzer Connect-PurviewPostureSession { $script:BothConnected }
        $null = Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'connect-both') -Connect -WarningVariable warns -WarningAction SilentlyContinue
        Should -Invoke Connect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
        @($warns | Where-Object { $_ -match 'skipping connect' }).Count | Should -Be 0
    }
    It 'both services failed: terminating error with the gallery-install hint, and collectors never run' {
        Mock -ModuleName PurviewPostureAnalyzer Get-ConnectionInformation { @() }
        Mock -ModuleName PurviewPostureAnalyzer Connect-PurviewPostureSession { $script:BothMissing }
        Mock -ModuleName PurviewPostureAnalyzer Get-PpaSensitivityLabels { $null }
        $err = { Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'connect-failed') -Connect -WarningAction SilentlyContinue } |
            Should -Throw -ExpectedMessage '*could not establish either service*' -PassThru
        $err.Exception.Message | Should -Match 'Install-Module ExchangeOnlineManagement'
        Should -Invoke Get-PpaSensitivityLabels -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
    }
}

Describe 'UX-1 -Disconnect' {
    It 'a completed run with -Disconnect calls Disconnect exactly once (every collector read failed internally - still a completed run)' {
        Mock -ModuleName PurviewPostureAnalyzer Disconnect-PurviewPostureSession { }
        $null = Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'disc-ok') -Disconnect -WarningAction SilentlyContinue
        Should -Invoke Disconnect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 1
    }
    It 'FINALLY PROOF: Disconnect is still called when the tenant-run body throws' {
        Mock -ModuleName PurviewPostureAnalyzer Disconnect-PurviewPostureSession { }
        Mock -ModuleName PurviewPostureAnalyzer Get-PpaRunContext { throw 'ppa-test: run-context boom' }
        { Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'disc-throw') -Disconnect -WarningAction SilentlyContinue } |
            Should -Throw -ExpectedMessage '*run-context boom*'
        Should -Invoke Disconnect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 1
    }
    It 'Disconnect is still called on the -Connect both-failed error path' {
        Mock -ModuleName PurviewPostureAnalyzer Get-ConnectionInformation { @() }
        Mock -ModuleName PurviewPostureAnalyzer Connect-PurviewPostureSession { $script:BothMissing }
        Mock -ModuleName PurviewPostureAnalyzer Disconnect-PurviewPostureSession { }
        { Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'disc-failed') -Connect -Disconnect -WarningAction SilentlyContinue } |
            Should -Throw -ExpectedMessage '*could not establish either service*'
        Should -Invoke Disconnect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 1
    }
}

Describe 'UX-1 -Show' {
    It 'a completed run with -Show opens the HTML report exactly once (mocked - no real browser)' {
        Mock -ModuleName PurviewPostureAnalyzer Invoke-Item { }
        $null = Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'show-ok') -Show -WarningAction SilentlyContinue
        Should -Invoke Invoke-Item -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter { [string]$LiteralPath -like '*posture-report.html' }
    }
    It 'a failed run with -Show never tries to open anything (no HtmlPath exists)' {
        Mock -ModuleName PurviewPostureAnalyzer Invoke-Item { }
        Mock -ModuleName PurviewPostureAnalyzer Get-PpaRunContext { throw 'ppa-test: run-context boom' }
        { Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'show-throw') -Show -WarningAction SilentlyContinue } |
            Should -Throw -ExpectedMessage '*run-context boom*'
        Should -Invoke Invoke-Item -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
    }
}

Describe 'UX-1 -UserPrincipalName without -Connect' {
    It 'warns once and never connects' {
        Mock -ModuleName PurviewPostureAnalyzer Connect-PurviewPostureSession { }
        $null = Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'upn-alone') -UserPrincipalName 'op@contoso.com' -WarningVariable warns -WarningAction SilentlyContinue
        @($warns | Where-Object { $_ -match 'only used with -Connect' }).Count | Should -Be 1
        Should -Invoke Connect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
    }
}

Describe 'UX-1 guest (B2B) forwarding (pre-publish Part 6)' {
    It '-Connect + guest params: all three connect knobs forwarded to Connect-PurviewPostureSession' {
        Mock -ModuleName PurviewPostureAnalyzer Get-ConnectionInformation { @() }
        Mock -ModuleName PurviewPostureAnalyzer Connect-PurviewPostureSession { $script:BothConnected }
        $null = Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'guest-fwd') -Connect `
            -UserPrincipalName 'you@yourfirm.com' -DelegatedOrganization 'client.onmicrosoft.com' `
            -AzureADAuthorizationEndpointUri 'https://login.microsoftonline.com/client.onmicrosoft.com' -WarningAction SilentlyContinue
        Should -Invoke Connect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            $UserPrincipalName -eq 'you@yourfirm.com' -and
            $DelegatedOrganization -eq 'client.onmicrosoft.com' -and
            $AzureADAuthorizationEndpointUri -eq 'https://login.microsoftonline.com/client.onmicrosoft.com'
        }
    }
    It '-DelegatedOrganization without -Connect: warned (consolidated), never forwarded' {
        Mock -ModuleName PurviewPostureAnalyzer Connect-PurviewPostureSession { }
        $null = Invoke-PurviewPostureAnalyzer -OutputDirectory (Join-Path $script:OutRoot 'guest-alone') `
            -DelegatedOrganization 'client.onmicrosoft.com' -WarningVariable warns -WarningAction SilentlyContinue
        @($warns | Where-Object { $_ -match 'only used with -Connect' -and $_ -match '-DelegatedOrganization' }).Count | Should -Be 1
        Should -Invoke Connect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
    }
    It 'delta mode ignores the guest params in the one consolidated warning; no connect' {
        Mock -ModuleName PurviewPostureAnalyzer Connect-PurviewPostureSession { }
        $threw = $false
        try {
            $null = Invoke-PurviewPostureAnalyzer -DeltaFrom (Join-Path $TestDrive 'a.json') -DeltaTo (Join-Path $TestDrive 'b.json') `
                -Connect -DelegatedOrganization 'client.onmicrosoft.com' `
                -AzureADAuthorizationEndpointUri 'https://login.microsoftonline.com/client.onmicrosoft.com' `
                -WarningVariable warns -WarningAction SilentlyContinue
        }
        catch { $threw = $true }
        $threw | Should -BeTrue
        @($warns | Where-Object { $_ -match 'Delta mode ignores' -and $_ -match '-DelegatedOrganization' -and $_ -match '-AzureADAuthorizationEndpointUri' }).Count | Should -Be 1
        Should -Invoke Connect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
    }
}

Describe 'UX-1 delta mode' {
    It 'ignores all four switches with one consolidated warning; no connect, no disconnect' {
        Mock -ModuleName PurviewPostureAnalyzer Connect-PurviewPostureSession { }
        Mock -ModuleName PurviewPostureAnalyzer Disconnect-PurviewPostureSession { }
        Mock -ModuleName PurviewPostureAnalyzer Invoke-Item { }
        # Missing snapshot files (pwsh 7) or the delta engine gate (PS 5.1) - either way
        # the delta call throws AFTER the switch warning, on both engines.
        $threw = $false
        try {
            $null = Invoke-PurviewPostureAnalyzer -DeltaFrom (Join-Path $TestDrive 'a.json') -DeltaTo (Join-Path $TestDrive 'b.json') `
                -Connect -Disconnect -Show -UserPrincipalName 'op@contoso.com' -WarningVariable warns -WarningAction SilentlyContinue
        }
        catch { $threw = $true }
        $threw | Should -BeTrue
        @($warns | Where-Object { $_ -match 'Delta mode ignores -Connect, -Disconnect, -Show, -UserPrincipalName' }).Count | Should -Be 1
        Should -Invoke Connect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
        Should -Invoke Disconnect-PurviewPostureSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
        Should -Invoke Invoke-Item -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
    }
}
