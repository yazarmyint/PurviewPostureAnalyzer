# Connect.Tests.ps1 - Connect-PurviewPostureSession parameter contract, incl. the
# cross-tenant guest / B2B calls (pre-publish Part 6). The money regression: with
# NO guest parameters, both Connect cmdlets are called exactly as before - no
# DelegatedOrganization, no AzureADAuthorizationEndpointUri. Guest contract
# (verified against MS Learn, module 3.0.0+): IPPS gets BOTH the organization and
# the auth endpoint (derived from the organization when not supplied); EXO gets
# the organization ALONE. The two ExchangeOnlineManagement Connect cmdlets are
# mocked at module scope - no real sign-in ever happens; global stubs give Pester
# a command to mock on boxes without the EXO module (SessionSwitches precedent).
# F-014: the chokepoint now opens with an EXO presence guard, so every contract
# test mocks the availability probe (Test-PpaExoModuleAvailable) to $true; the
# guard's own absence/presence coverage is the last Describe.
# Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:RepoRoot 'PurviewPostureAnalyzer.psd1') -Force

    # F-014 locked, operator-approved guard message - reproduced EXACTLY, including
    # the 4-space indent on the install line. Composed at runtime the same way the
    # source composes it, so no mutating-verb cmdlet literal appears here either.
    $script:PpaExoGuardMessage = @(
        'ExchangeOnlineManagement module not found.'
        'PurviewPostureAnalyzer needs it to connect to Microsoft Purview. PPA stopped before connecting.'
        ''
        'To install it, run:'
        ('    ' + 'Install' + '-Module ExchangeOnlineManagement -Scope CurrentUser')
        ''
        'Then run PurviewPostureAnalyzer again.'
    ) -join [Environment]::NewLine

    # Global stubs (dev box has no ExchangeOnlineManagement): parameter surfaces
    # mirror the real cmdlets' relevant subset - BOTH stubs accept the endpoint so
    # a regression that passes it to EXO binds cleanly and is CAUGHT by the
    # ParameterFilter assertions instead of dying as a binding error.
    function global:Connect-IPPSSession {
        [CmdletBinding()]
        param([string]$UserPrincipalName, [string]$DelegatedOrganization, [string]$AzureADAuthorizationEndpointUri, [bool]$ShowBanner)
    }
    function global:Connect-ExchangeOnline {
        [CmdletBinding()]
        param([string]$UserPrincipalName, [string]$DelegatedOrganization, [string]$AzureADAuthorizationEndpointUri, [bool]$ShowBanner)
    }
}

AfterAll {
    foreach ($fn in @('Connect-IPPSSession', 'Connect-ExchangeOnline')) {
        if (Test-Path "function:$fn") { Remove-Item "function:$fn" -Force -ErrorAction SilentlyContinue }
    }
    Remove-Module PurviewPostureAnalyzer -Force -ErrorAction SilentlyContinue
}

Describe 'Connect-PurviewPostureSession - host-tenant regression (no guest params)' {
    BeforeEach {
        # F-014: satisfy the presence guard so the connection contract is exercised.
        Mock -ModuleName PurviewPostureAnalyzer Test-PpaExoModuleAvailable { $true }
    }
    It 'calls IPPS and EXO with NO guest parameters and NO UPN - today''s behavior' {
        Mock -ModuleName PurviewPostureAnalyzer Connect-IPPSSession { }
        Mock -ModuleName PurviewPostureAnalyzer Connect-ExchangeOnline { }
        $r = Connect-PurviewPostureSession
        $r.SecurityCompliance | Should -Be 'connected'
        $r.ExchangeOnline     | Should -Be 'connected'
        Should -Invoke Connect-IPPSSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            (-not $PSBoundParameters.ContainsKey('DelegatedOrganization')) -and
            (-not $PSBoundParameters.ContainsKey('AzureADAuthorizationEndpointUri')) -and
            (-not $PSBoundParameters.ContainsKey('UserPrincipalName'))
        }
        Should -Invoke Connect-ExchangeOnline -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            (-not $PSBoundParameters.ContainsKey('DelegatedOrganization')) -and
            (-not $PSBoundParameters.ContainsKey('AzureADAuthorizationEndpointUri')) -and
            (-not $PSBoundParameters.ContainsKey('UserPrincipalName'))
        }
    }
    It '-UserPrincipalName alone is forwarded to both cmdlets, still with no guest parameters' {
        Mock -ModuleName PurviewPostureAnalyzer Connect-IPPSSession { }
        Mock -ModuleName PurviewPostureAnalyzer Connect-ExchangeOnline { }
        $null = Connect-PurviewPostureSession -UserPrincipalName 'op@contoso.com'
        Should -Invoke Connect-IPPSSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            $UserPrincipalName -eq 'op@contoso.com' -and (-not $PSBoundParameters.ContainsKey('DelegatedOrganization'))
        }
        Should -Invoke Connect-ExchangeOnline -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            $UserPrincipalName -eq 'op@contoso.com' -and (-not $PSBoundParameters.ContainsKey('DelegatedOrganization'))
        }
    }
}

Describe 'Connect-PurviewPostureSession - guest (B2B) calls' {
    BeforeEach {
        # F-014: satisfy the presence guard so the connection contract is exercised.
        Mock -ModuleName PurviewPostureAnalyzer Test-PpaExoModuleAvailable { $true }
    }
    It 'org only: IPPS gets the org AND the DERIVED endpoint; EXO gets the org and NO endpoint' {
        Mock -ModuleName PurviewPostureAnalyzer Connect-IPPSSession { }
        Mock -ModuleName PurviewPostureAnalyzer Connect-ExchangeOnline { }
        $null = Connect-PurviewPostureSession -DelegatedOrganization 'client.onmicrosoft.com'
        Should -Invoke Connect-IPPSSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            $DelegatedOrganization -eq 'client.onmicrosoft.com' -and
            $AzureADAuthorizationEndpointUri -eq 'https://login.microsoftonline.com/client.onmicrosoft.com'
        }
        Should -Invoke Connect-ExchangeOnline -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            $DelegatedOrganization -eq 'client.onmicrosoft.com' -and
            (-not $PSBoundParameters.ContainsKey('AzureADAuthorizationEndpointUri'))
        }
    }
    It 'explicit endpoint override: IPPS uses the EXPLICIT endpoint, not the derived one; EXO still endpoint-free' {
        Mock -ModuleName PurviewPostureAnalyzer Connect-IPPSSession { }
        Mock -ModuleName PurviewPostureAnalyzer Connect-ExchangeOnline { }
        $null = Connect-PurviewPostureSession -DelegatedOrganization 'client.onmicrosoft.com' `
            -AzureADAuthorizationEndpointUri 'https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555'
        Should -Invoke Connect-IPPSSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            $DelegatedOrganization -eq 'client.onmicrosoft.com' -and
            $AzureADAuthorizationEndpointUri -eq 'https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555'
        }
        Should -Invoke Connect-ExchangeOnline -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            $DelegatedOrganization -eq 'client.onmicrosoft.com' -and
            (-not $PSBoundParameters.ContainsKey('AzureADAuthorizationEndpointUri'))
        }
    }
    It 'endpoint WITHOUT org: warns once, and NEITHER cmdlet receives any guest parameter' {
        Mock -ModuleName PurviewPostureAnalyzer Connect-IPPSSession { }
        Mock -ModuleName PurviewPostureAnalyzer Connect-ExchangeOnline { }
        $null = Connect-PurviewPostureSession -AzureADAuthorizationEndpointUri 'https://login.microsoftonline.com/client.onmicrosoft.com' `
            -WarningVariable warns -WarningAction SilentlyContinue
        @($warns | Where-Object { $_ -match 'only used with -DelegatedOrganization' }).Count | Should -Be 1
        Should -Invoke Connect-IPPSSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            (-not $PSBoundParameters.ContainsKey('DelegatedOrganization')) -and
            (-not $PSBoundParameters.ContainsKey('AzureADAuthorizationEndpointUri'))
        }
        Should -Invoke Connect-ExchangeOnline -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            (-not $PSBoundParameters.ContainsKey('DelegatedOrganization')) -and
            (-not $PSBoundParameters.ContainsKey('AzureADAuthorizationEndpointUri'))
        }
    }
    It '-UserPrincipalName rides alongside the guest parameters on both cmdlets' {
        Mock -ModuleName PurviewPostureAnalyzer Connect-IPPSSession { }
        Mock -ModuleName PurviewPostureAnalyzer Connect-ExchangeOnline { }
        $null = Connect-PurviewPostureSession -UserPrincipalName 'you@yourfirm.com' -DelegatedOrganization 'client.onmicrosoft.com'
        Should -Invoke Connect-IPPSSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            $UserPrincipalName -eq 'you@yourfirm.com' -and
            $DelegatedOrganization -eq 'client.onmicrosoft.com' -and
            $AzureADAuthorizationEndpointUri -eq 'https://login.microsoftonline.com/client.onmicrosoft.com'
        }
        Should -Invoke Connect-ExchangeOnline -ModuleName PurviewPostureAnalyzer -Exactly -Times 1 -ParameterFilter {
            $UserPrincipalName -eq 'you@yourfirm.com' -and
            $DelegatedOrganization -eq 'client.onmicrosoft.com' -and
            (-not $PSBoundParameters.ContainsKey('AzureADAuthorizationEndpointUri'))
        }
    }
}

Describe 'Connect-PurviewPostureSession - ExchangeOnlineManagement presence guard (F-014)' {
    It 'ABSENT: terminating stop with the exact locked message, and NEITHER Connect cmdlet is attempted' {
        Mock -ModuleName PurviewPostureAnalyzer Test-PpaExoModuleAvailable { $false }
        Mock -ModuleName PurviewPostureAnalyzer Connect-IPPSSession { }
        Mock -ModuleName PurviewPostureAnalyzer Connect-ExchangeOnline { }
        $err = $null
        try { $null = Connect-PurviewPostureSession } catch { $err = $_ }
        $err | Should -Not -BeNullOrEmpty
        $err.Exception.Message | Should -BeExactly $script:PpaExoGuardMessage
        Should -Invoke Connect-IPPSSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
        Should -Invoke Connect-ExchangeOnline -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
    }
    It 'ABSENT: the guard also stops the guest (B2B) call before any connection work' {
        Mock -ModuleName PurviewPostureAnalyzer Test-PpaExoModuleAvailable { $false }
        Mock -ModuleName PurviewPostureAnalyzer Connect-IPPSSession { }
        Mock -ModuleName PurviewPostureAnalyzer Connect-ExchangeOnline { }
        $err = $null
        try { $null = Connect-PurviewPostureSession -DelegatedOrganization 'client.onmicrosoft.com' } catch { $err = $_ }
        $err | Should -Not -BeNullOrEmpty
        $err.Exception.Message | Should -BeExactly $script:PpaExoGuardMessage
        Should -Invoke Connect-IPPSSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
        Should -Invoke Connect-ExchangeOnline -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
    }
    It 'PRESENT: the guard stays silent - no terminating error, both connection calls proceed' {
        Mock -ModuleName PurviewPostureAnalyzer Test-PpaExoModuleAvailable { $true }
        Mock -ModuleName PurviewPostureAnalyzer Connect-IPPSSession { }
        Mock -ModuleName PurviewPostureAnalyzer Connect-ExchangeOnline { }
        $r = Connect-PurviewPostureSession
        $r.SecurityCompliance | Should -Be 'connected'
        $r.ExchangeOnline     | Should -Be 'connected'
        Should -Invoke Connect-IPPSSession -ModuleName PurviewPostureAnalyzer -Exactly -Times 1
        Should -Invoke Connect-ExchangeOnline -ModuleName PurviewPostureAnalyzer -Exactly -Times 1
    }
}
