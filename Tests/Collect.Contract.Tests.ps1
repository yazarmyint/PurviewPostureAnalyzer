# Collect.Contract.Tests.ps1 - Wave 4 Part A pins: the collector-side normalize
# contract. Every leaf a collector emits must be string / number / boolean / null;
# DateTimes become ISO-8601 UTC strings at normalize time; session artifacts
# (RunspaceId and friends) never survive; and every collector reports the
# per-collector outcome enum (Populated | Empty | Partial | AccessDenied |
# CmdletUnavailable | Failed | Skipped | NotRun). Runs under PS 5.1 AND 7+.
# Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot

    # Dot-source the whole Collect layer (mirrors the module loader) so new
    # Private\Collect helpers are always in scope without editing this list.
    foreach ($f in (Get-ChildItem -Path (Join-Path $script:RepoRoot 'Private\Collect') -Filter '*.ps1')) {
        . $f.FullName
    }

    # ---- read stub -------------------------------------------------------------
    # Redefines Invoke-PpaReadCmdlet AFTER the real one was dot-sourced, so the
    # collectors under test resolve this stub. Un-stubbed cmdlets degrade to
    # CommandNotFound, exactly like a disconnected session.
    $script:PpaReadStubMap = @{}
    function Invoke-PpaReadCmdlet {
        param([Parameter(Mandatory = $true)][string]$Name, [hashtable]$Arguments = @{})
        if ($script:PpaReadStubMap.ContainsKey($Name)) {
            $r = $script:PpaReadStubMap[$Name]
            return [pscustomobject]@{ Name = $Name; Status = [string]$r.Status; Data = @($r.Data); Error = $r.Error }
        }
        return [pscustomobject]@{ Name = $Name; Status = 'CommandNotFound'; Data = @(); Error = "Cmdlet '$Name' is not available in this session." }
    }

    # ---- primitive-leaf walker ---------------------------------------------------
    # Returns "path: TypeName" for every leaf that is not string/number/boolean/null.
    # Arrays, dictionaries and PSCustomObjects are structure and recurse; anything
    # else (DateTime, Guid, enum, ...) is a contract violation.
    $script:PpaAllowedLeafTypes = @(
        [string], [bool],
        [byte], [sbyte], [int16], [uint16], [int32], [uint32], [int64], [uint64],
        [single], [double], [decimal]
    )
    function Get-PpaLeafViolation {
        param($Value, [string]$Path = '$')
        $bad = New-Object System.Collections.Generic.List[string]
        if ($null -eq $Value) { return @() }
        foreach ($t in $script:PpaAllowedLeafTypes) { if ($Value -is $t) { return @() } }
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($k in @($Value.Keys)) {
                if ($k -isnot [string]) { $bad.Add(("{0} (key): {1}" -f $Path, $k.GetType().FullName)) }
                foreach ($v in (Get-PpaLeafViolation -Value $Value[$k] -Path ("{0}.{1}" -f $Path, $k))) { $bad.Add($v) }
            }
            return $bad.ToArray()
        }
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            foreach ($p in $Value.PSObject.Properties) {
                foreach ($v in (Get-PpaLeafViolation -Value $p.Value -Path ("{0}.{1}" -f $Path, $p.Name))) { $bad.Add($v) }
            }
            return $bad.ToArray()
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            $i = 0
            foreach ($item in $Value) {
                foreach ($v in (Get-PpaLeafViolation -Value $item -Path ("{0}[{1}]" -f $Path, $i))) { $bad.Add($v) }
                $i++
            }
            return $bad.ToArray()
        }
        return @(("{0}: {1}" -f $Path, $Value.GetType().FullName))
    }

    $script:PpaOutcomeEnum = @('Populated', 'Empty', 'Partial', 'AccessDenied', 'CmdletUnavailable', 'Failed', 'Skipped', 'NotRun')
    $script:PpaIsoPattern  = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'

    # ---- rich live-shaped stub map -------------------------------------------------
    # Raw cmdlet objects the way a live IPPS session hands them over: DateTime-typed
    # dates, Guid-typed ids, enum-ish values, session artifacts. Collectors must
    # normalize ALL of it to primitive leaves.
    function Get-PpaRichStubMap {
        $polGuid = [guid]'11111111-2222-3333-4444-555555555555'
        return @{
            'Get-DlpCompliancePolicy' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{
                    Name = 'HIPAA Policy'; Guid = $polGuid; Mode = [System.DayOfWeek]::Monday
                    ExchangeLocation = @('All'); SharePointLocation = @(); OneDriveLocation = @()
                    TeamsLocation = @(); EndpointDlpLocation = @()
                    LastStatusChangeDate = [datetime]::new(2026, 5, 12, 14, 30, 0, [System.DateTimeKind]::Utc)
                    EnforcementPlanes = @('CopilotExperiences')
                    Locations = '[{"Workload":"Applications","Location":"Copilot.M365","LocationSource":"PurviewConfig"}]'
                    Comment = 'Prevent data leakage and oversharing by restricting Microsoft 365 Copilot access'
                    WhenCreated = [datetime]::new(2026, 4, 1, 9, 0, 0, [System.DateTimeKind]::Utc)
                }) }
            'Get-DlpComplianceRule' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{
                    Name = 'r-hipaa'; Guid = [guid]'aaaaaaaa-0000-0000-0000-000000000001'
                    ParentPolicyName = 'HIPAA Policy'; Policy = $polGuid; Disabled = $false
                    ContentContainsSensitiveInformation = @(@{ Name = 'U.S. SSN' }, @{ Name = 'Credit Card Number' })
                }) }
            'Get-RetentionCompliancePolicy' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{
                    Name = 'HR 7yr'; Guid = $polGuid
                    SharePointLocation = @('All'); ExchangeLocation = @(); ModernGroupLocation = @()
                    OneDriveLocation = @(); AdaptiveScopeLocation = @()
                }) }
            'Get-RetentionComplianceRule' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{ Name = 'HR-Retain-7y'; Guid = [guid]'aaaaaaaa-0000-0000-0000-000000000009'; Policy = $polGuid; ParentPolicyName = 'HR 7yr'; ContentMatchQuery = ''; ContentContainsSensitiveInformation = @() }) }
            'Get-AdaptiveScope' = @{ Status = 'Ok'; Data = @() }
            'Get-Label' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{ DisplayName = 'Confidential'; Name = 'conf'; Guid = $polGuid; Priority = 2; ContentType = 'File, Email'; ParentId = [guid]::Empty }) }
            'Get-LabelPolicy' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{ Name = 'Global Policy'; Guid = [guid]'aaaaaaaa-0000-0000-0000-000000000002'; Labels = @('Confidential'); Enabled = $true; ExchangeLocation = @('All'); ModernGroupLocation = @() }) }
            'Get-AutoSensitivityLabelPolicy' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{
                    Name = 'Auto PHI'; Guid = [guid]'aaaaaaaa-0000-0000-0000-000000000003'; Mode = 'TestWithoutNotifications'
                    SensitiveInformationTypeNames = @('U.S. HIPAA')
                    SimulationStartDate = [datetime]::new(2026, 4, 8, 0, 0, 0, [System.DateTimeKind]::Utc)
                    SimulationItemCount = 2140
                }) }
            'Get-InsiderRiskPolicy' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{ Name = 'IRM_Tenant_Setting_abc'; InsiderRiskScenario = 'TenantSetting' },
                [pscustomobject]@{ Name = 'Data theft'; Guid = [guid]'aaaaaaaa-0000-0000-0000-000000000005'; InsiderRiskScenario = 'DataTheft'; Workload = @('Exchange', 'Teams'); WhenCreatedUTC = [datetime]::new(2026, 3, 15, 8, 0, 0, [System.DateTimeKind]::Utc) }) }
            'Get-AdminAuditLogConfig' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{ UnifiedAuditLogIngestionEnabled = $true }) }
            'Get-OrganizationConfig' = @{ Status = 'Ok'; Data = @([pscustomobject]@{ Name = 'contoso' }) }
            'Get-ComplianceCase' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{ Name = 'Case-1'; Guid = [guid]'aaaaaaaa-0000-0000-0000-000000000004'; Status = 'Active' }) }
            'Get-SupervisoryReviewPolicyV2' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{ Name = 'Copilot interactions'; Guid = [guid]'aaaaaaaa-0000-0000-0000-000000000007'; Enabled = $true }) }
            'Get-SupervisoryReviewRule' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{ Name = 'Copilot interactions'; ContentSources = '[{"RevieweeName":"AllUsersGroupsOfTenant","Workloads":["Copilot"],"ThirdPartyWorkloads":null,"UnifiedGenAIWorkloads":null}]' }) }
            'Get-DspmPolicy' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{
                    Name = 'DSPM-1'; Guid = [guid]'aaaaaaaa-0000-0000-0000-000000000008'; Mode = 'Enable'
                    RunspaceId = [guid]::NewGuid(); PSComputerName = 'ipps.contoso.net'
                    PSShowComputerName = $false; PSSourceJobInstanceId = [guid]::NewGuid()
                }) }
            'Get-AppRetentionCompliancePolicy' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{ Name = 'Copilot retention'; Guid = [guid]'aaaaaaaa-0000-0000-0000-000000000006'; Enabled = $true; Applications = @('User:M365Copilot') }) }
        }
    }
}

Describe 'Primitive-leaf contract - checked-in fixtures' {
    It 'every leaf in every normalized fixture is string/number/boolean/null' {
        $fixtures = @(
            Get-ChildItem -Path (Join-Path $script:RepoRoot 'Samples\sample-raw') -Filter '*.json'
            Get-ChildItem -Path (Join-Path $script:RepoRoot 'Samples\sample-raw\sparse') -Filter '*.json'
            Get-Item -Path (Join-Path $script:RepoRoot 'Samples\sample-normalized.json')
            Get-Item -Path (Join-Path $script:RepoRoot 'Samples\sample-normalized-dense.json')
        )
        $fixtures.Count | Should -BeGreaterThan 10
        $violations = New-Object System.Collections.Generic.List[string]
        foreach ($f in $fixtures) {
            $obj = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($v in (Get-PpaLeafViolation -Value $obj -Path $f.Name)) { $violations.Add($v) }
        }
        ($violations -join "`n") | Should -BeNullOrEmpty
    }
}

Describe 'Primitive-leaf contract - live-shaped collector output' {
    BeforeEach { $script:PpaReadStubMap = @{} }
    It 'every collector normalizes live-shaped raw objects to primitive leaves only' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $violations = New-Object System.Collections.Generic.List[string]
        $outputs = @{
            'Get-PpaSensitivityLabels' = (Get-PpaSensitivityLabels)
            'Get-PpaDlp'               = (Get-PpaDlp)
            'Get-PpaRetention'         = (Get-PpaRetention)
            'Get-PpaInsiderRisk'       = (Get-PpaInsiderRisk)
            'Get-PpaAudit'             = (Get-PpaAudit)
            'Get-PpaEdiscovery'        = (Get-PpaEdiscovery)
            'Get-PpaCommsCompliance'   = (Get-PpaCommsCompliance)
            'Get-PpaDspmAi'            = (Get-PpaDspmAi)
        }
        foreach ($name in $outputs.Keys) {
            foreach ($v in (Get-PpaLeafViolation -Value $outputs[$name] -Path $name)) { $violations.Add($v) }
        }
        ($violations -join "`n") | Should -BeNullOrEmpty
    }
}

Describe 'ISO-8601 date normalization (re-pinned rule: dates are ISO-8601 UTC strings)' {
    BeforeEach { $script:PpaReadStubMap = @{} }
    It 'DLP testModeSince is an ISO-8601 UTC string when the cmdlet returns a DateTime' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $out = Get-PpaDlp
        $out.policies.items[0].testModeSince | Should -Be '2026-05-12T14:30:00Z'
    }
    It 'auto-label simulationStartDate is an ISO-8601 UTC string when the cmdlet returns a DateTime' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $out = Get-PpaSensitivityLabels
        $out.autoLabels.items[0].simulationStartDate | Should -Be '2026-04-08T00:00:00Z'
    }
    It 'passes fixture-style date STRINGS through unchanged' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-DlpCompliancePolicy'].Data[0].LastStatusChangeDate = '2026-05-12'
        (Get-PpaDlp).policies.items[0].testModeSince | Should -Be '2026-05-12'
    }
    It 'normalizes an absent date to an empty string' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-DlpCompliancePolicy'].Data[0].LastStatusChangeDate = $null
        (Get-PpaDlp).policies.items[0].testModeSince | Should -Be ''
    }
    It 'normalizes the DateTime.MinValue placeholder to an empty string (never "since 01-Jan-0001")' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-DlpCompliancePolicy'].Data[0].LastStatusChangeDate = [datetime]::MinValue
        (Get-PpaDlp).policies.items[0].testModeSince | Should -Be ''
    }
}

Describe 'Session artifact stripping (A.3)' {
    BeforeEach { $script:PpaReadStubMap = @{} }
    It 'strips RunspaceId / PSComputerName / PSShowComputerName / PSSourceJobInstanceId from generic projections' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $out = Get-PpaDspmAi
        $names = @($out.dspmPolicies.items[0].props | ForEach-Object { $_.n })
        $names | Should -Contain 'Mode'
        $names | Should -Not -Contain 'RunspaceId'
        $names | Should -Not -Contain 'PSComputerName'
        $names | Should -Not -Contain 'PSShowComputerName'
        $names | Should -Not -Contain 'PSSourceJobInstanceId'
    }
}

Describe 'Location scope projection (Part D: matrix grounding, documented-only)' {
    BeforeEach { $script:PpaReadStubMap = @{} }
    It 'DLP policies project locationScope (All/Scoped/None) and locationExceptions per workload' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-DlpCompliancePolicy'].Data[0].ExchangeLocation = @('All')
        $script:PpaReadStubMap['Get-DlpCompliancePolicy'].Data[0].SharePointLocation = @('https://contoso.sharepoint.com/sites/hr')
        $script:PpaReadStubMap['Get-DlpCompliancePolicy'].Data[0] | Add-Member -NotePropertyName SharePointLocationException -NotePropertyValue @('https://contoso.sharepoint.com/sites/legal') -Force
        $p = (Get-PpaDlp).policies.items[0]
        $p.locationScope.exchange | Should -Be 'All'
        $p.locationScope.sharePoint | Should -Be 'Scoped'
        $p.locationScope.oneDrive | Should -Be 'None'
        $p.locationScope.powerBI | Should -Be 'None'   # property absent on the raw -> None
        $p.locationExceptions.sharePoint | Should -BeTrue
        $p.locationExceptions.exchange | Should -BeFalse
    }
    It 'auto-label policies project the documented three-workload locationScope' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-AutoSensitivityLabelPolicy'].Data[0] | Add-Member -NotePropertyName ExchangeLocation -NotePropertyValue @('All') -Force
        $script:PpaReadStubMap['Get-AutoSensitivityLabelPolicy'].Data[0] | Add-Member -NotePropertyName OneDriveLocation -NotePropertyValue @() -Force
        $a = (Get-PpaSensitivityLabels).autoLabels.items[0]
        $a.locationScope.exchange | Should -Be 'All'
        $a.locationScope.oneDrive | Should -Be 'None'
        $a.locationExceptions.exchange | Should -BeFalse
    }
    It 'retention policies project locationScope incl. the documented Teams locations' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-RetentionCompliancePolicy'].Data[0] | Add-Member -NotePropertyName TeamsChannelLocation -NotePropertyValue @('All') -Force
        $r = (Get-PpaRetention).policies.items[0]
        $r.locationScope.sharePoint | Should -Be 'All'
        $r.locationScope.teamsChannel | Should -Be 'All'
        $r.locationScope.teamsChat | Should -Be 'None'
        # The legacy locations token array is untouched (analyzer contract).
        @($r.locations) | Should -Contain 'SharePoint'
    }
}

Describe 'Resolve-PpaCollectorOutcome mapping (A.4)' {
    It 'all reads Ok with items -> Populated' {
        Resolve-PpaCollectorOutcome -ReadStatuses @('Ok', 'Ok') -ItemCount 3 | Should -Be 'Populated'
    }
    It 'all reads Ok with zero items -> Empty' {
        Resolve-PpaCollectorOutcome -ReadStatuses @('Ok') -ItemCount 0 | Should -Be 'Empty'
    }
    It 'some reads Ok, some failed -> Partial (regardless of item count)' {
        Resolve-PpaCollectorOutcome -ReadStatuses @('Ok', 'AccessDenied') -ItemCount 5 | Should -Be 'Partial'
        Resolve-PpaCollectorOutcome -ReadStatuses @('Ok', 'CommandNotFound') -ItemCount 0 | Should -Be 'Partial'
    }
    It 'no read Ok, all AccessDenied -> AccessDenied' {
        Resolve-PpaCollectorOutcome -ReadStatuses @('AccessDenied', 'AccessDenied') -ItemCount 0 | Should -Be 'AccessDenied'
    }
    It 'no read Ok, all CommandNotFound -> CmdletUnavailable' {
        Resolve-PpaCollectorOutcome -ReadStatuses @('CommandNotFound') -ItemCount 0 | Should -Be 'CmdletUnavailable'
    }
    It 'no read Ok, errors -> Failed (Blocked counts as Failed)' {
        Resolve-PpaCollectorOutcome -ReadStatuses @('Error') -ItemCount 0 | Should -Be 'Failed'
        Resolve-PpaCollectorOutcome -ReadStatuses @('Blocked') -ItemCount 0 | Should -Be 'Failed'
    }
    It 'mixed failures with no Ok: AccessDenied > CmdletUnavailable > Failed' {
        Resolve-PpaCollectorOutcome -ReadStatuses @('AccessDenied', 'CommandNotFound', 'Error') -ItemCount 0 | Should -Be 'AccessDenied'
        Resolve-PpaCollectorOutcome -ReadStatuses @('CommandNotFound', 'Error') -ItemCount 0 | Should -Be 'CmdletUnavailable'
    }
}

Describe 'Per-collector outcome (A.4)' {
    BeforeEach { $script:PpaReadStubMap = @{} }
    It 'every collector emits an outcome from the closed enum (disconnected session)' {
        # Default stub: everything CommandNotFound, like running without a session.
        $collectors = @(
            (Get-PpaSensitivityLabels), (Get-PpaDlp), (Get-PpaRetention), (Get-PpaInsiderRisk),
            (Get-PpaAudit), (Get-PpaEdiscovery), (Get-PpaCommsCompliance), (Get-PpaDspmAi)
        )
        foreach ($c in $collectors) {
            $script:PpaOutcomeEnum | Should -Contain $c.outcome
            $c.outcome | Should -Be 'CmdletUnavailable'
        }
    }
    It 'a fully populated run reports Populated on every collector' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        foreach ($c in @((Get-PpaSensitivityLabels), (Get-PpaDlp), (Get-PpaRetention), (Get-PpaInsiderRisk),
                         (Get-PpaAudit), (Get-PpaEdiscovery), (Get-PpaCommsCompliance), (Get-PpaDspmAi))) {
            $c.outcome | Should -Be 'Populated'
        }
    }
    It 'labels: the by-design NotCollected containers block does NOT drag the outcome to Partial' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        (Get-PpaSensitivityLabels).outcome | Should -Be 'Populated'
    }
    It 'DLP: policies readable but rules denied -> Partial' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-DlpComplianceRule'] = @{ Status = 'AccessDenied'; Data = @(); Error = 'denied' }
        (Get-PpaDlp).outcome | Should -Be 'Partial'
    }
    It 'audit: readable with zero config objects -> Empty' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-AdminAuditLogConfig'] = @{ Status = 'Ok'; Data = @(); Error = $null }
        (Get-PpaAudit).outcome | Should -Be 'Empty'
    }
    It 'comms compliance: readable with zero policies -> Empty' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-SupervisoryReviewPolicyV2'] = @{ Status = 'Ok'; Data = @(); Error = $null }
        (Get-PpaCommsCompliance).outcome | Should -Be 'Empty'
    }
    It 'insider risk: only the TenantSetting pseudo-policy present -> Empty, not Populated' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-InsiderRiskPolicy'] = @{ Status = 'Ok'; Data = @(
            [pscustomobject]@{ Name = 'IRM_Tenant_Setting_abc'; InsiderRiskScenario = 'TenantSetting' }); Error = $null }
        (Get-PpaInsiderRisk).outcome | Should -Be 'Empty'
    }
    It 'retention: all reads Ok and nothing configured -> Empty' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-RetentionCompliancePolicy'] = @{ Status = 'Ok'; Data = @(); Error = $null }
        $script:PpaReadStubMap['Get-RetentionComplianceRule']   = @{ Status = 'Ok'; Data = @(); Error = $null }
        (Get-PpaRetention).outcome | Should -Be 'Empty'
    }
    It 'never emits Skipped or NotRun from a collector that actually ran' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        foreach ($c in @((Get-PpaDlp), (Get-PpaAudit))) {
            $c.outcome | Should -Not -BeIn @('Skipped', 'NotRun')
        }
    }
}

Describe 'Opportunistic Guid capture (A.5)' {
    # Keying rule Guid -> Identity -> Name only works if normalizers project the
    # Guid the cmdlets document. Property-presence check only - no new reads.
    BeforeEach { $script:PpaReadStubMap = @{} }

    It 'captures the raw Guid on every item type when the cmdlet provides one' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $labels = Get-PpaSensitivityLabels
        $dlp    = Get-PpaDlp
        $ret    = Get-PpaRetention
        $irm    = Get-PpaInsiderRisk
        $ed     = Get-PpaEdiscovery
        $dspm   = Get-PpaDspmAi

        $dlp.policies.items[0].guid          | Should -Be '11111111-2222-3333-4444-555555555555'
        $dlp.rules.items[0].guid             | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
        $labels.policies.items[0].guid       | Should -Be 'aaaaaaaa-0000-0000-0000-000000000002'
        $labels.autoLabels.items[0].guid     | Should -Be 'aaaaaaaa-0000-0000-0000-000000000003'
        $ret.policies.items[0].guid          | Should -Be '11111111-2222-3333-4444-555555555555'
        $ret.labels.items[0].guid            | Should -Be 'aaaaaaaa-0000-0000-0000-000000000009'
        $irm.policies.items[0].guid          | Should -Be 'aaaaaaaa-0000-0000-0000-000000000005'
        $ed.cases.items[0].guid              | Should -Be 'aaaaaaaa-0000-0000-0000-000000000004'
        $dspm.copilotPolicies.items[0].guid  | Should -Be '11111111-2222-3333-4444-555555555555'
        $dspm.dspmPolicies.items[0].guid     | Should -Be 'aaaaaaaa-0000-0000-0000-000000000008'
        $dspm.appRetention.items[0].guid     | Should -Be 'aaaaaaaa-0000-0000-0000-000000000006'
        $dspm.ccCopilot.items[0].guid        | Should -Be 'aaaaaaaa-0000-0000-0000-000000000007'
    }

    It 'falls back cleanly to an empty guid (Name keying) when the raw object has no Guid' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        foreach ($cmdlet in @('Get-DlpCompliancePolicy', 'Get-DlpComplianceRule')) {
            foreach ($o in $script:PpaReadStubMap[$cmdlet].Data) { $o.PSObject.Properties.Remove('Guid') }
        }
        $dlp = Get-PpaDlp
        $dlp.policies.items[0].PSObject.Properties.Name | Should -Contain 'guid'
        $dlp.policies.items[0].guid | Should -Be ''
        $dlp.policies.items[0].name | Should -Be 'HIPAA Policy'
        $dlp.rules.items[0].guid    | Should -Be ''
    }

    It 'treats the empty Guid (all zeros) as absent - falls back to Name keying' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-ComplianceCase'].Data[0].Guid = [guid]::Empty
        (Get-PpaEdiscovery).cases.items[0].guid | Should -Be ''
    }

    It 'DspmPolicy props bag excludes Guid - it duplicates the top-level guid identity field' {
        # Denylist candidate resolved at Part C: excluded at normalize time rather
        # than denylisted, so the compare-time denylist stays property-name-based.
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $item = (Get-PpaDspmAi).dspmPolicies.items[0]
        $item.guid | Should -Be 'aaaaaaaa-0000-0000-0000-000000000008'
        @($item.props | ForEach-Object { $_.n }) | Should -Not -Contain 'Guid'
    }
    It 'guid values are primitive strings (leaf walk stays green)' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $violations = @()
        foreach ($out in @((Get-PpaDlp), (Get-PpaSensitivityLabels), (Get-PpaRetention), (Get-PpaDspmAi))) {
            $violations += @(Get-PpaLeafViolation -Value $out -Path 'out')
        }
        ($violations -join "`n") | Should -BeNullOrEmpty
    }
}
