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

    # ---- auto-labeling AdvancedRule harness (Wave 5 cleanup Part 2) --------------
    # Fixture of record: the committed real Get-AutoSensitivityLabelRule capture
    # (grouped = bracket-repaired parseable blob; malformed = the as-pasted
    # truncated string). Helpers live here per the Pester 5 top-level BeforeAll rule.
    function Get-PpaAlrFixture {
        [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-raw\autolabel-advancedrule.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    function Get-PpaAlrExpectedNames {
        # The RULED pin (maintainer-confirmed at Part 2 kickoff): 10 distinct names
        # from the real blob - 7 named SITs + 3 trainable classifiers - in
        # ordinal-ignore-case sorted order.
        @(
            'All Full Names'
            'All Medical Terms And Conditions'
            'Business - Health care'
            'Drug Enforcement Agency (DEA) Number'
            'Employee Insurance Files'
            'Health/Medical Forms'
            'International Classification of Diseases (ICD-10-CM)'
            'International Classification of Diseases (ICD-9-CM)'
            'U.S. Physical Addresses'
            'U.S. Social Security Number (SSN)'
        )
    }
    function New-PpaAutoLabelStubMap {
        # Minimal labels-collector stub: one auto-label policy whose rules are the
        # test's to shape. The policy name matches the fixture rules'
        # ParentPolicyName so association exercises the reference path.
        param($PolicySits = @(), $Rules = @(), [string]$RulesStatus = 'Ok')
        @{
            'Get-Label'       = @{ Status = 'Ok'; Data = @() }
            'Get-LabelPolicy' = @{ Status = 'Ok'; Data = @() }
            'Get-AutoSensitivityLabelPolicy' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{
                    Name = 'Auto-label grouped health data'; Guid = [guid]'bbbbbbbb-0000-0000-0000-000000000001'
                    Mode = 'Enable'; SensitiveInformationTypeNames = @($PolicySits)
                }) }
            'Get-AutoSensitivityLabelRule' = @{ Status = $RulesStatus; Data = @($Rules) }
        }
    }

    # ---- label GUID resolution harness (pre-publish Part 4) ---------------------
    # Raw-TENANT-shaped label reads: Get-Label exposes BOTH Guid and ImmutableId;
    # Get-LabelPolicy's .Labels references labels by those ids, never by display
    # name - the shape the hand-authored sample fixtures never exercised.
    # $PolicyLabels is the policy's .Labels array under test.
    function New-PpaLabelResolutionStubMap {
        param($PolicyLabels = @())
        @{
            'Get-Label' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{
                    DisplayName = 'Confidential'; Name = 'confidential-1a2b'
                    Guid = [guid]'cccccccc-0000-0000-0000-000000000001'
                    ImmutableId = [guid]'dddddddd-0000-0000-0000-000000000001'
                    Priority = 1; ContentType = 'File, Email'
                }
                [pscustomobject]@{
                    DisplayName = 'Highly Confidential'; Name = 'highconf-3c4d'
                    Guid = [guid]'cccccccc-0000-0000-0000-000000000002'
                    ImmutableId = [guid]'dddddddd-0000-0000-0000-000000000002'
                    Priority = 2; ContentType = 'File, Email'
                }
            ) }
            'Get-LabelPolicy' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{
                    Name = 'Global publish'; Guid = [guid]'aaaaaaaa-0000-0000-0000-000000000010'
                    Labels = @($PolicyLabels); Enabled = $true
                    ExchangeLocation = @('All'); ModernGroupLocation = @()
                }
            ) }
            'Get-AutoSensitivityLabelPolicy' = @{ Status = 'Ok'; Data = @() }
            'Get-AutoSensitivityLabelRule'   = @{ Status = 'Ok'; Data = @() }
        }
    }

    # ---- retention label resolution harness (pre-publish Part 7) ----------------
    # Raw-TENANT-shaped retention reads: a label-publishing rule carries an
    # auto-GUID .Name with the label in PublishComplianceTag / ApplyComplianceTag
    # (either may itself be a GUID); Get-ComplianceTag is the friendly-name
    # inventory. $Rules and $Tags are the shapes under test.
    function New-PpaRetentionResolutionStubMap {
        param($Rules = @(), $Tags = @())
        @{
            'Get-RetentionCompliancePolicy' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{
                    Name = 'HR 7yr'; Guid = [guid]'aaaaaaaa-1111-0000-0000-000000000001'
                    SharePointLocation = @('All'); ExchangeLocation = @(); ModernGroupLocation = @()
                    OneDriveLocation = @(); AdaptiveScopeLocation = @()
                }
            ) }
            'Get-RetentionComplianceRule' = @{ Status = 'Ok'; Data = @($Rules) }
            'Get-AdaptiveScope'           = @{ Status = 'Ok'; Data = @() }
            'Get-ComplianceTag'           = @{ Status = 'Ok'; Data = @($Tags) }
        }
    }

    # ---- DSPM label-reference harness (pre-publish Part 8) ----------------------
    # One Copilot-scoped DLP policy (EnforcementPlanes carries the VERIFIED
    # CopilotExperiences token) whose rule's label conditions are the shape under
    # test; Get-Label is the friendly-name inventory. On a live tenant the .name
    # of a label condition carries the label GUID, never the display name.
    function New-PpaDspmLabelRefStubMap {
        param($Rules = @())
        @{
            'Get-DlpCompliancePolicy' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{
                    Name = 'Copilot guard'; Guid = [guid]'aaaaaaaa-2222-0000-0000-000000000001'
                    Mode = 'Enable'; EnforcementPlanes = @('CopilotExperiences')
                }
            ) }
            'Get-DlpComplianceRule'            = @{ Status = 'Ok'; Data = @($Rules) }
            'Get-DspmPolicy'                   = @{ Status = 'Ok'; Data = @() }
            'Get-AppRetentionCompliancePolicy' = @{ Status = 'Ok'; Data = @() }
            'Get-RetentionCompliancePolicy'    = @{ Status = 'Ok'; Data = @() }
            'Get-SupervisoryReviewPolicyV2'    = @{ Status = 'Ok'; Data = @() }
            'Get-SupervisoryReviewRule'        = @{ Status = 'Ok'; Data = @() }
            'Get-Label' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{
                    DisplayName = 'Highly Confidential'; Name = 'highconf-internal'
                    Guid = [guid]'cccccccc-1111-0000-0000-000000000001'
                    ImmutableId = [guid]'dddddddd-1111-0000-0000-000000000001'
                }
            ) }
        }
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
            'Get-ComplianceTag' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{ Name = 'HR-Retain-7y'; Guid = [guid]'bbbbbbbb-0000-0000-0000-000000000101' }) }
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
                [pscustomobject]@{ Name = 'Data theft'; Guid = [guid]'aaaaaaaa-0000-0000-0000-000000000005'; InsiderRiskScenario = 'DataTheft'; Mode = 'Enable'; Workload = @('Exchange', 'Teams'); WhenCreatedUTC = [datetime]::new(2026, 3, 15, 8, 0, 0, [System.DateTimeKind]::Utc) }) }
            'Get-AdminAuditLogConfig' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{ UnifiedAuditLogIngestionEnabled = $true }) }
            'Get-IRMConfiguration' = @{ Status = 'Ok'; Data = @(
                [pscustomobject]@{ AzureRMSLicensingEnabled = $true }) }
            'Get-OrganizationConfig' = @{ Status = 'Ok'; Data = @([pscustomobject]@{ Name = 'contoso'; AuditDisabled = $false }) }
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
    It 'labels: projects the Azure RMS state (AzureRMSLicensingEnabled) as a real boolean' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $out = Get-PpaSensitivityLabels
        $out.PSObject.Properties.Name | Should -Contain 'irmConfig'
        $out.irmConfig.azureRmsEnabled | Should -BeOfType [bool]
        $out.irmConfig.azureRmsEnabled | Should -BeTrue
    }
    It 'labels: a degraded Get-IRMConfiguration read projects null and does NOT drag the outcome (containers precedent)' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-IRMConfiguration'] = @{ Status = 'CommandNotFound'; Data = @(); Error = 'no EXO session' }
        $out = Get-PpaSensitivityLabels
        ($null -eq $out.irmConfig.azureRmsEnabled) | Should -BeTrue
        $out.irmConfig.status | Should -Be 'CommandNotFound'
        $out.outcome | Should -Be 'Populated'
    }
    It 'labels: a missing AzureRMSLicensingEnabled property projects null - never a guessed boolean' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-IRMConfiguration'] = @{ Status = 'Ok'; Data = @([pscustomobject]@{ Name = 'irm' }); Error = $null }
        $out = Get-PpaSensitivityLabels
        $out.PSObject.Properties.Name | Should -Contain 'irmConfig'
        ($null -eq $out.irmConfig.azureRmsEnabled) | Should -BeTrue
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
    It 'audit: projects the org-level mailbox auditing override (AuditDisabled) as a real boolean' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $out = Get-PpaAudit
        $out.PSObject.Properties.Name | Should -Contain 'mailboxAuditingDisabled'
        $out.mailboxAuditingDisabled | Should -BeOfType [bool]
        $out.mailboxAuditingDisabled | Should -BeFalse
    }
    It 'audit: a missing AuditDisabled property projects null - never a guessed boolean' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-OrganizationConfig'] = @{ Status = 'Ok'; Data = @([pscustomobject]@{ Name = 'contoso' }); Error = $null }
        $out = Get-PpaAudit
        $out.PSObject.Properties.Name | Should -Contain 'mailboxAuditingDisabled'
        ($null -eq $out.mailboxAuditingDisabled) | Should -BeTrue
    }
    It 'audit: a failed org read projects null for the mailbox auditing override' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-OrganizationConfig'] = @{ Status = 'AccessDenied'; Data = @(); Error = 'denied' }
        $out = Get-PpaAudit
        $out.PSObject.Properties.Name | Should -Contain 'mailboxAuditingDisabled'
        ($null -eq $out.mailboxAuditingDisabled) | Should -BeTrue
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
    It 'insider risk: projects the policy Mode as-is for scenario-coverage gating (IRM-04/05)' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $item = @((Get-PpaInsiderRisk).policies.items)[0]
        $item.PSObject.Properties.Name | Should -Contain 'mode'
        $item.mode | Should -Be 'Enable'
    }
    It 'insider risk: a missing Mode property projects an empty string - never invented' {
        $script:PpaReadStubMap = Get-PpaRichStubMap
        $script:PpaReadStubMap['Get-InsiderRiskPolicy'] = @{ Status = 'Ok'; Data = @(
            [pscustomobject]@{ Name = 'Old shape'; InsiderRiskScenario = 'DataTheft' }); Error = $null }
        $item = @((Get-PpaInsiderRisk).policies.items)[0]
        $item.PSObject.Properties.Name | Should -Contain 'mode'
        $item.mode | Should -Be ''
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

Describe 'Label policy GUID resolution (pre-publish Part 4)' {
    # On a live tenant Get-LabelPolicy's .Labels carries label GUIDs/ImmutableIds,
    # not names - raw ids leaked straight into LABELS-02 because the collector
    # passed them through. The collector must resolve every entry through the
    # label inventory (keyed on Guid AND ImmutableId, raw Name as last resort)
    # and preserve unknown entries verbatim: a deleted-but-still-referenced
    # label must still show something, never vanish.
    BeforeEach { $script:PpaReadStubMap = @{} }

    It 'resolves Guid-keyed .Labels entries to display names (raw-tenant shape, case-insensitive)' {
        $script:PpaReadStubMap = New-PpaLabelResolutionStubMap -PolicyLabels @(
            'cccccccc-0000-0000-0000-000000000001', 'CCCCCCCC-0000-0000-0000-000000000002')
        $pol = (Get-PpaSensitivityLabels).policies.items[0]
        @($pol.labels) | Should -Be @('Confidential', 'Highly Confidential')
    }
    It 'resolves ImmutableId-keyed .Labels entries too (the dual-key map)' {
        $script:PpaReadStubMap = New-PpaLabelResolutionStubMap -PolicyLabels @(
            'dddddddd-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000001')
        $pol = (Get-PpaSensitivityLabels).policies.items[0]
        @($pol.labels) | Should -Be @('Highly Confidential', 'Confidential')
    }
    It 'preserves an orphan .Labels entry verbatim (deleted-but-referenced label)' {
        $script:PpaReadStubMap = New-PpaLabelResolutionStubMap -PolicyLabels @(
            'cccccccc-0000-0000-0000-000000000001', 'eeeeeeee-9999-9999-9999-999999999999')
        $pol = (Get-PpaSensitivityLabels).policies.items[0]
        @($pol.labels) | Should -Be @('Confidential', 'eeeeeeee-9999-9999-9999-999999999999')
    }
    It 'resolves via the raw internal Name as a last resort' {
        $script:PpaReadStubMap = New-PpaLabelResolutionStubMap -PolicyLabels @('highconf-3c4d')
        @((Get-PpaSensitivityLabels).policies.items[0].labels) | Should -Be @('Highly Confidential')
    }
    It 'passes name-based fixture .Labels through unchanged (sample regression shape)' {
        # A display name is neither a Guid, an ImmutableId nor the internal Name
        # key -> verbatim fallback, so the checked-in sample fixtures render as before.
        $script:PpaReadStubMap = New-PpaLabelResolutionStubMap -PolicyLabels @('Confidential')
        @((Get-PpaSensitivityLabels).policies.items[0].labels) | Should -Be @('Confidential')
    }
    It 'keeps the projected labels a flat array of plain strings' {
        $script:PpaReadStubMap = New-PpaLabelResolutionStubMap -PolicyLabels @(
            'cccccccc-0000-0000-0000-000000000001', 'eeeeeeee-9999-9999-9999-999999999999')
        foreach ($v in @((Get-PpaSensitivityLabels).policies.items[0].labels)) { $v | Should -BeOfType [string] }
    }
    It 'captures the label ImmutableId alongside guid in the inventory' {
        $script:PpaReadStubMap = New-PpaLabelResolutionStubMap
        $lab = (Get-PpaSensitivityLabels).labels.items[0]
        $lab.guid        | Should -Be 'cccccccc-0000-0000-0000-000000000001'
        $lab.immutableId | Should -Be 'dddddddd-0000-0000-0000-000000000001'
    }
    It 'projects an empty immutableId when the raw label lacks the property' {
        $script:PpaReadStubMap = New-PpaLabelResolutionStubMap
        $script:PpaReadStubMap['Get-Label'].Data[0].PSObject.Properties.Remove('ImmutableId')
        (Get-PpaSensitivityLabels).labels.items[0].immutableId | Should -Be ''
    }
}

Describe 'Retention label resolution (pre-publish Part 7)' {
    # On a live tenant a label-publishing retention rule has an auto-GUID .Name;
    # the published label lives in PublishComplianceTag / ApplyComplianceTag,
    # which MAY themselves hold a GUID. The collector prefers the tag reference,
    # resolves GUID-valued references through the Get-ComplianceTag inventory,
    # and preserves anything unresolvable verbatim.
    BeforeEach { $script:PpaReadStubMap = @{} }

    It 'auto-GUID rule name + PublishComplianceTag name: policy labels and label item show the tag, never the GUID' {
        $script:PpaReadStubMap = New-PpaRetentionResolutionStubMap -Rules @(
            [pscustomobject]@{ Name = 'dddddddd-aaaa-bbbb-cccc-000000000001'; Guid = [guid]'dddddddd-aaaa-bbbb-cccc-000000000001'; ParentPolicyName = 'HR 7yr'; PublishComplianceTag = 'Fin-Retain-10y'; ContentMatchQuery = ''; ContentContainsSensitiveInformation = @() }
        ) -Tags @([pscustomobject]@{ Name = 'Fin-Retain-10y'; Guid = [guid]'cccccccc-0000-0000-0000-000000000201' })
        $out = Get-PpaRetention
        @($out.policies.items[0].labels) | Should -Be @('Fin-Retain-10y')
        $out.labels.items[0].name        | Should -Be 'Fin-Retain-10y'
        # the auto-GUID rule name never leaks into a display field (guid identity field aside)
        @($out.policies.items[0].labels) | Should -Not -Contain 'dddddddd-aaaa-bbbb-cccc-000000000001'
    }
    It 'GUID-valued PublishComplianceTag resolves through Get-ComplianceTag to the friendly name' {
        $script:PpaReadStubMap = New-PpaRetentionResolutionStubMap -Rules @(
            [pscustomobject]@{ Name = 'dddddddd-aaaa-bbbb-cccc-000000000002'; ParentPolicyName = 'HR 7yr'; PublishComplianceTag = 'cccccccc-0000-0000-0000-000000000201'; ContentMatchQuery = ''; ContentContainsSensitiveInformation = @() }
        ) -Tags @([pscustomobject]@{ Name = 'Fin-Retain-10y'; Guid = [guid]'cccccccc-0000-0000-0000-000000000201' })
        $out = Get-PpaRetention
        @($out.policies.items[0].labels) | Should -Be @('Fin-Retain-10y')
        $out.labels.items[0].name        | Should -Be 'Fin-Retain-10y'
    }
    It 'plain retention rule (no Publish/ApplyComplianceTag) falls back to .Name verbatim - no regression' {
        $script:PpaReadStubMap = New-PpaRetentionResolutionStubMap -Rules @(
            [pscustomobject]@{ Name = 'HR-Retain-7y'; ParentPolicyName = 'HR 7yr'; ContentMatchQuery = ''; ContentContainsSensitiveInformation = @() }
        ) -Tags @([pscustomobject]@{ Name = 'Fin-Retain-10y'; Guid = [guid]'cccccccc-0000-0000-0000-000000000201' })
        $out = Get-PpaRetention
        @($out.policies.items[0].labels) | Should -Be @('HR-Retain-7y')
        $out.labels.items[0].name        | Should -Be 'HR-Retain-7y'
    }
    It 'unresolvable reference (no tag match) passes through verbatim - orphan fallback' {
        $script:PpaReadStubMap = New-PpaRetentionResolutionStubMap -Rules @(
            [pscustomobject]@{ Name = 'dddddddd-aaaa-bbbb-cccc-000000000003'; ParentPolicyName = 'HR 7yr'; PublishComplianceTag = 'eeeeeeee-9999-9999-9999-999999999999'; ContentMatchQuery = ''; ContentContainsSensitiveInformation = @() }
        ) -Tags @([pscustomobject]@{ Name = 'Fin-Retain-10y'; Guid = [guid]'cccccccc-0000-0000-0000-000000000201' })
        $out = Get-PpaRetention
        $out.labels.items[0].name | Should -Be 'eeeeeeee-9999-9999-9999-999999999999'
    }
    It 'ApplyComplianceTag resolves when PublishComplianceTag is absent (auto-applied labels)' {
        $script:PpaReadStubMap = New-PpaRetentionResolutionStubMap -Rules @(
            [pscustomobject]@{ Name = 'dddddddd-aaaa-bbbb-cccc-000000000004'; ParentPolicyName = 'HR 7yr'; ApplyComplianceTag = 'cccccccc-0000-0000-0000-000000000201'; ContentMatchQuery = 'kql'; ContentContainsSensitiveInformation = @() }
        ) -Tags @([pscustomobject]@{ Name = 'Fin-Retain-10y'; Guid = [guid]'cccccccc-0000-0000-0000-000000000201' })
        $out = Get-PpaRetention
        $out.labels.items[0].name      | Should -Be 'Fin-Retain-10y'
        $out.labels.items[0].autoApply | Should -BeTrue
    }
    It 'keeps the projected labels a flat array of plain strings' {
        $script:PpaReadStubMap = New-PpaRetentionResolutionStubMap -Rules @(
            [pscustomobject]@{ Name = 'dddddddd-aaaa-bbbb-cccc-000000000001'; ParentPolicyName = 'HR 7yr'; PublishComplianceTag = 'Fin-Retain-10y'; ContentMatchQuery = ''; ContentContainsSensitiveInformation = @() }
        ) -Tags @([pscustomobject]@{ Name = 'Fin-Retain-10y'; Guid = [guid]'cccccccc-0000-0000-0000-000000000201' })
        $out = Get-PpaRetention
        foreach ($v in @($out.policies.items[0].labels)) { $v | Should -BeOfType [string] }
        $out.labels.items[0].name | Should -BeOfType [string]
    }
    It 'a failed Get-ComplianceTag read degrades the outcome to Partial (folded into ReadStatuses)' {
        $script:PpaReadStubMap = New-PpaRetentionResolutionStubMap -Rules @(
            [pscustomobject]@{ Name = 'HR-Retain-7y'; ParentPolicyName = 'HR 7yr'; ContentMatchQuery = ''; ContentContainsSensitiveInformation = @() }
        )
        $script:PpaReadStubMap['Get-ComplianceTag'] = @{ Status = 'AccessDenied'; Data = @(); Error = 'denied' }
        $out = Get-PpaRetention
        $out.outcome | Should -Be 'Partial'
        # resolution still degrades gracefully: verbatim rule name, never a crash
        $out.labels.items[0].name | Should -Be 'HR-Retain-7y'
    }
}

Describe 'DSPM label reference resolution (pre-publish Part 8)' {
    # On a live tenant a DLP rule's sensitivity-label condition carries the label
    # GUID in .name; the collector resolves each reference through the Get-Label
    # inventory (Guid + ImmutableId + Name -> DisplayName) with verbatim fallback,
    # so AI-03's labelRefs show friendly names, never GUIDs. The AdvancedRule
    # text-scan (hasLabelCondition boolean) is unchanged.
    BeforeEach { $script:PpaReadStubMap = @{} }

    It 'GUID-keyed label condition (group form) resolves to the DisplayName, and hasLabelCondition is true' {
        $script:PpaReadStubMap = New-PpaDspmLabelRefStubMap -Rules @(
            [pscustomobject]@{
                Name = 'r-copilot'; ParentPolicyName = 'Copilot guard'
                ContentContainsSensitiveInformation = @(
                    [pscustomobject]@{ groups = @([pscustomobject]@{ labels = @(
                        [pscustomobject]@{ type = 'Sensitivity'; name = 'cccccccc-1111-0000-0000-000000000001' }
                    ) }) }
                )
            }
        )
        $item = (Get-PpaDspmAi).copilotPolicies.items[0]
        @($item.labelRefs) | Should -Be @('Highly Confidential')
        $item.hasLabelCondition | Should -BeTrue
    }
    It 'flat-entry reference keyed on ImmutableId resolves too (dual-key map + flat branch)' {
        $script:PpaReadStubMap = New-PpaDspmLabelRefStubMap -Rules @(
            [pscustomobject]@{
                Name = 'r-copilot'; ParentPolicyName = 'Copilot guard'
                ContentContainsSensitiveInformation = @(
                    [pscustomobject]@{ type = 'Sensitivity'; name = 'dddddddd-1111-0000-0000-000000000001' }
                )
            }
        )
        $item = (Get-PpaDspmAi).copilotPolicies.items[0]
        @($item.labelRefs) | Should -Be @('Highly Confidential')
        $item.hasLabelCondition | Should -BeTrue
    }
    It 'an already-friendly / unmapped name passes through verbatim - no regression' {
        $script:PpaReadStubMap = New-PpaDspmLabelRefStubMap -Rules @(
            [pscustomobject]@{
                Name = 'r-copilot'; ParentPolicyName = 'Copilot guard'
                ContentContainsSensitiveInformation = @(
                    [pscustomobject]@{ groups = @([pscustomobject]@{ labels = @(
                        [pscustomobject]@{ type = 'Sensitivity'; name = 'Highly Confidential' },
                        [pscustomobject]@{ type = 'Sensitivity'; name = 'Custom Label X' }
                    ) }) }
                )
            }
        )
        $item = (Get-PpaDspmAi).copilotPolicies.items[0]
        @($item.labelRefs) | Should -Be @('Highly Confidential', 'Custom Label X')
    }
    It 'no label condition: hasLabelCondition false, labelRefs empty - unchanged' {
        $script:PpaReadStubMap = New-PpaDspmLabelRefStubMap -Rules @(
            [pscustomobject]@{
                Name = 'r-copilot'; ParentPolicyName = 'Copilot guard'
                ContentContainsSensitiveInformation = @(@{ Name = 'U.S. SSN' })
            }
        )
        $item = (Get-PpaDspmAi).copilotPolicies.items[0]
        $item.hasLabelCondition | Should -BeFalse
        @($item.labelRefs).Count | Should -Be 0
    }
    It 'AdvancedRule-only label mention: hasLabelCondition true, labelRefs empty - unchanged' {
        $script:PpaReadStubMap = New-PpaDspmLabelRefStubMap -Rules @(
            [pscustomobject]@{
                Name = 'r-copilot'; ParentPolicyName = 'Copilot guard'
                ContentContainsSensitiveInformation = @()
                AdvancedRule = '{"Condition":{"SubConditions":[{"ConditionName":"ContentContainsSensitiveInformation","Value":[{"groups":[{"labels":[{"type":"Sensitivity","id":"x"}]}]}]}]}}'
            }
        )
        $item = (Get-PpaDspmAi).copilotPolicies.items[0]
        $item.hasLabelCondition | Should -BeTrue
        @($item.labelRefs).Count | Should -Be 0
    }
    It 'a failed Get-Label read degrades the outcome to Partial and resolution falls back verbatim' {
        $script:PpaReadStubMap = New-PpaDspmLabelRefStubMap -Rules @(
            [pscustomobject]@{
                Name = 'r-copilot'; ParentPolicyName = 'Copilot guard'
                ContentContainsSensitiveInformation = @(
                    [pscustomobject]@{ groups = @([pscustomobject]@{ labels = @(
                        [pscustomobject]@{ type = 'Sensitivity'; name = 'cccccccc-1111-0000-0000-000000000001' }
                    ) }) }
                )
            }
        )
        $script:PpaReadStubMap['Get-Label'] = @{ Status = 'AccessDenied'; Data = @(); Error = 'denied' }
        $out = Get-PpaDspmAi
        $out.outcome | Should -Be 'Partial'
        @($out.copilotPolicies.items[0].labelRefs) | Should -Be @('cccccccc-1111-0000-0000-000000000001')
    }
}

Describe 'Auto-labeling AdvancedRule capture (Wave 5 cleanup Part 2)' {
    # Grouped-condition auto-label policies leave the flat property empty; the SITs
    # live in the rule-level AdvancedRule JSON. The collector reads
    # Get-AutoSensitivityLabelRule, flattens the names (SITs + trainable classifiers,
    # AND/OR groups discarded) into sits, and stamps conditionsSource so the analyzer
    # can render flat / grouped / unparsed / none / unreadable distinctly. Expected
    # values below are the RULED pin from the committed real capture
    # (Samples/sample-raw/autolabel-advancedrule.json): 10 distinct names, ordinal-
    # ignore-case sorted - maintainer-confirmed at Part 2 kickoff.
    BeforeEach { $script:PpaReadStubMap = @{} }

    It 'grouped: flat empty + parseable AdvancedRule -> the pinned 10-name sorted flat set' {
        $script:PpaReadStubMap = New-PpaAutoLabelStubMap -Rules @((Get-PpaAlrFixture).grouped)
        $a = (Get-PpaSensitivityLabels).autoLabels.items[0]
        @($a.sits) | Should -Be (Get-PpaAlrExpectedNames)
        $a.conditionsSource | Should -Be 'grouped'
    }
    It 'grouped: trainable classifiers from the blob are captured, never dropped' {
        $script:PpaReadStubMap = New-PpaAutoLabelStubMap -Rules @((Get-PpaAlrFixture).grouped)
        $sits = @((Get-PpaSensitivityLabels).autoLabels.items[0].sits)
        $sits | Should -Contain 'Business - Health care'
        $sits | Should -Contain 'Employee Insurance Files'
        $sits | Should -Contain 'Health/Medical Forms'
    }
    It 'malformed: the as-pasted truncated blob -> conditionsSource unparsed, empty sits' {
        # The fixture's malformed rule carries its own policy name; re-parent it to
        # the stub policy so the association holds and the blob itself is what fails.
        $mal = [pscustomobject]@{
            Name = 'Auto-label grouped health data'; ParentPolicyName = 'Auto-label grouped health data'
            AdvancedRule = [string](Get-PpaAlrFixture).malformed.AdvancedRule
        }
        $script:PpaReadStubMap = New-PpaAutoLabelStubMap -Rules @($mal)
        $a = (Get-PpaSensitivityLabels).autoLabels.items[0]
        $a.conditionsSource | Should -Be 'unparsed'
        @($a.sits).Count | Should -Be 0
    }
    It 'none: flat empty and no AdvancedRule on the rule -> conditionsSource none' {
        $bare = [pscustomobject]@{ Name = 'Auto-label grouped health data'; ParentPolicyName = 'Auto-label grouped health data' }
        $script:PpaReadStubMap = New-PpaAutoLabelStubMap -Rules @($bare)
        (Get-PpaSensitivityLabels).autoLabels.items[0].conditionsSource | Should -Be 'none'
    }
    It 'none: flat empty and no associated rule at all -> conditionsSource none' {
        $script:PpaReadStubMap = New-PpaAutoLabelStubMap -Rules @()
        (Get-PpaSensitivityLabels).autoLabels.items[0].conditionsSource | Should -Be 'none'
    }
    It 'flat populated stays untouched: cmdlet order kept, source flat, AdvancedRule ignored' {
        $script:PpaReadStubMap = New-PpaAutoLabelStubMap -PolicySits @('U.S. HIPAA', 'Credit Card Number') -Rules @((Get-PpaAlrFixture).grouped)
        $a = (Get-PpaSensitivityLabels).autoLabels.items[0]
        @($a.sits) | Should -Be @('U.S. HIPAA', 'Credit Card Number')
        $a.conditionsSource | Should -Be 'flat'
    }
    It 'rule read failure + empty flat -> conditionsSource unreadable; rulesStatus surfaced' {
        $script:PpaReadStubMap = New-PpaAutoLabelStubMap -Rules @() -RulesStatus 'AccessDenied'
        $out = Get-PpaSensitivityLabels
        $out.autoLabels.items[0].conditionsSource | Should -Be 'unreadable'
        $out.autoLabels.rulesStatus | Should -Be 'AccessDenied'
    }
    It 'the rule read NEVER degrades the collector outcome (containers precedent)' {
        $script:PpaReadStubMap = New-PpaAutoLabelStubMap -Rules @() -RulesStatus 'CommandNotFound'
        (Get-PpaSensitivityLabels).outcome | Should -Be 'Populated'
    }
    It 'rules are associated by Policy/ParentPolicyName reference or name equality, not position' {
        $other = [pscustomobject]@{ Name = 'Unrelated rule'; ParentPolicyName = 'Some other policy'; AdvancedRule = [string](Get-PpaAlrFixture).grouped.AdvancedRule }
        $script:PpaReadStubMap = New-PpaAutoLabelStubMap -Rules @($other)
        (Get-PpaSensitivityLabels).autoLabels.items[0].conditionsSource | Should -Be 'none'
    }
}
