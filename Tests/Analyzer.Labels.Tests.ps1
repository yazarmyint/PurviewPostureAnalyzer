# Analyzer.Labels.Tests.ps1 - the Sensitivity Labels analyzer reproduces the catalog
# logic from a raw fixture (no tenant). Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'Private\Model\PpaStatus.ps1')
    . (Join-Path $script:RepoRoot 'Private\Model\New-PpaFinding.ps1')
    . (Join-Path $script:RepoRoot 'Private\Model\New-PpaSection.ps1')
    . (Join-Path $script:RepoRoot 'Private\Core\Get-PpaLicenseRequirements.ps1')
    . (Join-Path $script:RepoRoot 'Private\Analyze\Invoke-PpaLabelAnalyzer.ps1')

    $script:Raw = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-raw\labels.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    # Pin AsOf to the sample report date so the simulation-age remark is deterministic.
    $script:Sec = Invoke-PpaLabelAnalyzer -Raw $script:Raw -AsOf ([datetime]'2026-06-24')
    $script:F = @{}
    foreach ($f in $script:Sec.findings) { $script:F[$f.id] = $f }
}

Describe 'Sensitivity Labels analyzer - shape' {
    It 'produces five findings LABELS-01..05 in order' {
        @($script:Sec.findings.id) | Should -Be @('LABELS-01', 'LABELS-02', 'LABELS-03', 'LABELS-04', 'LABELS-05')
    }
    It 'is the Sensitivity_Labels section under Microsoft Information Protection' {
        $script:Sec.id | Should -Be 'Sensitivity_Labels'
        $script:Sec.group | Should -Be 'Microsoft Information Protection'
    }
}

Describe 'LABELS-05 Azure Rights Management (Exchange Online)' {
    It 'is OK with the Enabled row pinned when AzureRMSLicensingEnabled is true (fixture)' {
        $f = $script:F['LABELS-05']
        $f.status | Should -Be 'OK'
        $f.table.rows[0].cells[0] | Should -Be 'Azure Rights Management (Exchange Online)'
        $f.table.rows[0].cells[1] | Should -Be 'Enabled'
    }
    It 'is Improvement with a deliberate-opt-out context row when disabled' {
        $raw2 = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-raw\labels.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $raw2 | Add-Member -NotePropertyName 'irmConfig' -NotePropertyValue ([pscustomobject]@{ status = 'Ok'; error = $null; azureRmsEnabled = $false }) -Force
        $sec2 = Invoke-PpaLabelAnalyzer -Raw $raw2 -AsOf ([datetime]'2026-06-24')
        $f = @($sec2.findings | Where-Object { $_.id -eq 'LABELS-05' })[0]
        $f.status | Should -Be 'Improvement'
        $f.title | Should -Be 'Azure Rights Management is disabled for Exchange Online'
        $f.table.rows[0].cells[1] | Should -Be 'Disabled (AzureRMSLicensingEnabled = false)'
        $f.table.rows[1].status | Should -Be 'Informational'
    }
    It 'is Verify manually when the EXO read degrades - never a false Disabled' {
        $raw3 = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-raw\labels.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $raw3 | Add-Member -NotePropertyName 'irmConfig' -NotePropertyValue ([pscustomobject]@{ status = 'CommandNotFound'; error = 'x'; azureRmsEnabled = $null }) -Force
        $sec3 = Invoke-PpaLabelAnalyzer -Raw $raw3 -AsOf ([datetime]'2026-06-24')
        @($sec3.findings | Where-Object { $_.id -eq 'LABELS-05' })[0].status | Should -Be 'Verify manually'
    }
    It 'is Verify manually when the raw shape predates the irmConfig block (older captures)' {
        $raw4 = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-raw\labels-autolabel-cases.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $sec4 = Invoke-PpaLabelAnalyzer -Raw $raw4 -AsOf ([datetime]'2026-07-01')
        @($sec4.findings | Where-Object { $_.id -eq 'LABELS-05' })[0].status | Should -Be 'Verify manually'
    }
}

Describe 'LABELS-01 taxonomy' {
    It 'is Informational when labels exist' { $script:F['LABELS-01'].status | Should -Be 'Informational' }
    It 'lists all six labels with two indented sub-labels' {
        @($script:F['LABELS-01'].table.rows).Count | Should -Be 6
        @($script:F['LABELS-01'].table.rows | Where-Object { $_.indent }).Count | Should -Be 2
    }
    It 'renders a sub-label as parent \ child and maps scope tokens to display' {
        $legal = $script:F['LABELS-01'].table.rows | Where-Object { $_.cells[0] -like '*Legal*' }
        $legal.cells[0] | Should -Be 'Highly Confidential \ Legal'
        ($script:F['LABELS-01'].table.rows | Where-Object { $_.cells[0] -eq 'Public' }).cells[2] | Should -Be 'Files, Emails'
    }
}

Describe 'LABELS-02 published' {
    It 'is OK when an enabled policy publishes labels to users' { $script:F['LABELS-02'].status | Should -Be 'OK' }
    It 'lists each label policy with its assignment' {
        @($script:F['LABELS-02'].table.rows).Count | Should -Be 2
        ($script:F['LABELS-02'].table.rows | Where-Object { $_.cells[0] -like 'Executive*' }).cells[2] | Should -Be 'Executives (grp)'
    }
}

Describe 'LABELS-03 auto-labeling' {
    It 'is Improvement when a policy is in simulation' { $script:F['LABELS-03'].status | Should -Be 'Improvement' }
    It 'titles the finding as not enforcing' { $script:F['LABELS-03'].title | Should -Be 'Auto-labeling is not enforcing' }
    It 'shows Simulation mode and a dated remark with the computed age' {
        $row = $script:F['LABELS-03'].table.rows[0]
        $row.cells[2] | Should -Be 'Simulation'
        $row.remark | Should -Match 'since 08-Apr-2026 \(77 days\)'
        $row.remark | Should -Match '2,140 items'
    }
}

Describe 'LABELS-04 containers' {
    It 'is a Recommendation when no container-scoped labels exist' { $script:F['LABELS-04'].status | Should -Be 'Recommendation' }
    It 'reports coverage from collected container inventory' {
        ($script:F['LABELS-04'].table.rows | Where-Object { $_.cells[0] -like '*Groups*' }).cells[1] | Should -Be '0 of 143 labeled'
        ($script:F['LABELS-04'].table.rows | Where-Object { $_.cells[0] -like 'SharePoint*' }).cells[1] | Should -Be '0 of 168 labeled'
    }
}

Describe 'LABELS-04 without container inventory (v1 live default)' {
    It 'shows Verify manually coverage rows but stays a Recommendation' {
        $raw2 = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-raw\labels.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $raw2.containers = [pscustomobject]@{ status = 'NotCollected'; groups = $null; sites = $null }
        $sec2 = Invoke-PpaLabelAnalyzer -Raw $raw2 -AsOf ([datetime]'2026-06-24')
        $f04 = $sec2.findings | Where-Object { $_.id -eq 'LABELS-04' }
        $f04.status | Should -Be 'Recommendation'
        @($f04.table.rows | Where-Object { $_.status -eq 'Verify manually' }).Count | Should -Be 2
    }
}

Describe 'section glance' {
    It 'summarizes label + policy counts and auto-label state' {
        $script:Sec.glance.metric | Should -Be '6 labels'
        $script:Sec.glance.sub | Should -Match 'auto-label in sim'
    }
}

Describe 'LABELS-03 condition states (Wave 5 cleanup Part 2: grouped AdvancedRule parsing)' {
    # The Conditions (SITs) cell must make four outcomes visually distinct:
    #   flat (unchanged) | grouped (flat sorted list + distinct count) |
    #   unparsed ("present - not parsed") | none ("None detected")
    # plus the rules-unreadable degrade. The grouped expectations are the RULED pin
    # from the real capture (Samples/sample-raw/autolabel-advancedrule.json).
    BeforeAll {
        $script:GroupedNames = @(
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
        function New-PpaAutoCaseItem {
            param([string]$Name, [string[]]$Sits, [string]$Source)
            $o = [pscustomobject]@{
                name = $Name; guid = "guid-$Name"; mode = 'Enforce'
                locationScope      = [pscustomobject]@{ exchange = 'All'; sharePoint = 'All'; oneDrive = 'All' }
                locationExceptions = [pscustomobject]@{ exchange = $false; sharePoint = $false; oneDrive = $false }
                sits = @($Sits); simulationStartDate = ''; simulationItemCount = 0
            }
            if (-not [string]::IsNullOrEmpty($Source)) {
                $o | Add-Member -NotePropertyName conditionsSource -NotePropertyValue $Source
            }
            return $o
        }
        function New-PpaAutoCaseRaw {
            param($Items)
            [pscustomobject]@{
                outcome    = 'Populated'
                labels     = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() }
                policies   = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() }
                autoLabels = [pscustomobject]@{ status = 'Ok'; error = $null; rulesStatus = 'Ok'; rulesError = $null; items = @($Items) }
                containers = [pscustomobject]@{ status = 'NotCollected'; groups = $null; sites = $null }
            }
        }
        $sec = Invoke-PpaLabelAnalyzer -Raw (New-PpaAutoCaseRaw @(
            (New-PpaAutoCaseItem 'flat-case' @('Credit Card Number', 'U.S. SSN') 'flat')
            (New-PpaAutoCaseItem 'grouped-case' $script:GroupedNames 'grouped')
            (New-PpaAutoCaseItem 'unparsed-case' @() 'unparsed')
            (New-PpaAutoCaseItem 'none-case' @() 'none')
            (New-PpaAutoCaseItem 'unreadable-case' @() 'unreadable')
        )) -AsOf ([datetime]'2026-07-01')
        $script:F03b = $sec.findings | Where-Object { $_.id -eq 'LABELS-03' }
        $script:CaseRow = @{}
        foreach ($r in $script:F03b.table.rows) { $script:CaseRow[$r.cells[0]] = $r }
    }
    It 'case 1 flat: the joined flat list renders unchanged' {
        $script:CaseRow['flat-case'].cells[1] | Should -Be 'Credit Card Number, U.S. SSN'
        $script:CaseRow['flat-case'].status | Should -Be 'OK'
    }
    It 'case 2 grouped: renders the sorted flat name list plus the distinct total count' {
        $script:CaseRow['grouped-case'].cells[1] | Should -Be (($script:GroupedNames -join ', ') + ' - 10 distinct (grouped conditions)')
    }
    It 'case 2 grouped: trainable classifiers appear in the rendered list' {
        $script:CaseRow['grouped-case'].cells[1] | Should -Match 'Business - Health care'
        $script:CaseRow['grouped-case'].cells[1] | Should -Match 'Employee Insurance Files'
        $script:CaseRow['grouped-case'].cells[1] | Should -Match 'Health/Medical Forms'
    }
    It 'case 3 unparsed: "present - not parsed", Verify manually, portal remark' {
        $script:CaseRow['unparsed-case'].cells[1] | Should -Be 'Conditions present - not parsed'
        $script:CaseRow['unparsed-case'].status | Should -Be 'Verify manually'
        $script:CaseRow['unparsed-case'].remark | Should -Match 'Purview portal'
    }
    It 'case 4 none: reads "None detected" with the row status untouched' {
        $script:CaseRow['none-case'].cells[1] | Should -Be 'None detected'
        $script:CaseRow['none-case'].status | Should -Be 'OK'
    }
    It 'rules-unreadable degrade: distinct wording, Verify manually' {
        $script:CaseRow['unreadable-case'].cells[1] | Should -Be 'Conditions not readable this run'
        $script:CaseRow['unreadable-case'].status | Should -Be 'Verify manually'
    }
    It 'the three empty-flat renderings are pairwise distinct' {
        $texts = @(
            $script:CaseRow['unparsed-case'].cells[1]
            $script:CaseRow['none-case'].cells[1]
            $script:CaseRow['unreadable-case'].cells[1]
        )
        $texts[0] | Should -Not -Be $texts[1]
        $texts[0] | Should -Not -Be $texts[2]
        $texts[1] | Should -Not -Be $texts[2]
        foreach ($t in $texts) { $t | Should -Not -BeNullOrEmpty }
    }
    It 'legacy shape (no conditionsSource marker) keeps the old rendering exactly' {
        $legacyItems = @(
            (New-PpaAutoCaseItem 'legacy-flat' @('U.S. HIPAA') '')
            (New-PpaAutoCaseItem 'legacy-empty' @() '')
        )
        $secL = Invoke-PpaLabelAnalyzer -Raw (New-PpaAutoCaseRaw $legacyItems) -AsOf ([datetime]'2026-07-01')
        $f = $secL.findings | Where-Object { $_.id -eq 'LABELS-03' }
        ($f.table.rows | Where-Object { $_.cells[0] -eq 'legacy-flat' }).cells[1] | Should -Be 'U.S. HIPAA'
        ($f.table.rows | Where-Object { $_.cells[0] -eq 'legacy-empty' }).cells[1] | Should -Be ''
    }
    It 'a simulating grouped policy keeps BOTH the simulation remark and the grouped tag' {
        $sim = New-PpaAutoCaseItem 'sim-grouped' $script:GroupedNames 'grouped'
        $sim.mode = 'TestWithoutNotifications'
        $sim.simulationStartDate = '2026-04-08'
        $sim.simulationItemCount = 2140
        $secS = Invoke-PpaLabelAnalyzer -Raw (New-PpaAutoCaseRaw @($sim)) -AsOf ([datetime]'2026-06-24')
        $row = ($secS.findings | Where-Object { $_.id -eq 'LABELS-03' }).table.rows[0]
        $row.cells[1] | Should -Match '10 distinct \(grouped conditions\)'
        $row.cells[2] | Should -Be 'Simulation'
        $row.remark | Should -Match 'since 08-Apr-2026 \(77 days\)'
    }
}

Describe 'LABELS-01 scope display mapping (Wave 5 cleanup Part 3)' {
    # Internal-name -> friendly-name mapping applied at the display boundary only.
    # Seeded with the maintainer-confirmed Teamwork -> Teams; the table maps ONLY
    # values confirmed to render today (no speculative entries), and unconfirmed
    # internal tokens pass through raw so nothing renders as a wrong guess.
    BeforeAll {
        $script:CasesRaw = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Samples\sample-raw\labels-autolabel-cases.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $script:SecCases = Invoke-PpaLabelAnalyzer -Raw $script:CasesRaw -AsOf ([datetime]'2026-07-01')
        $script:F01c = $script:SecCases.findings | Where-Object { $_.id -eq 'LABELS-01' }
    }
    It 'renders Teams for the fixture label whose raw scope is Teamwork' {
        $row = $script:F01c.table.rows | Where-Object { $_.cells[0] -eq 'Meetings - Confidential' }
        $row.cells[2] | Should -Be 'Files, Emails, Teams'
    }
    It 'the fixture itself still carries the raw Teamwork value (mapping is display-time only)' {
        @(($script:CasesRaw.labels.items | Where-Object { $_.name -eq 'Meetings - Confidential' }).scopes) | Should -Contain 'Teamwork'
    }
    It 'an unconfirmed internal token passes through raw - the table never guesses' {
        $raw = [pscustomobject]@{
            outcome    = 'Populated'
            labels     = [pscustomobject]@{ status = 'Ok'; error = $null; items = @(
                [pscustomobject]@{ name = 'Future label'; guid = 'guid-future'; priority = 1; scopes = @('File', 'SomeFutureInternalScope'); parentId = '' }) }
            policies   = [pscustomobject]@{ status = 'Ok'; error = $null; items = @() }
            autoLabels = [pscustomobject]@{ status = 'Ok'; error = $null; rulesStatus = 'Ok'; rulesError = $null; items = @() }
            containers = [pscustomobject]@{ status = 'NotCollected'; groups = $null; sites = $null }
        }
        $sec = Invoke-PpaLabelAnalyzer -Raw $raw -AsOf ([datetime]'2026-07-01')
        $f01 = $sec.findings | Where-Object { $_.id -eq 'LABELS-01' }
        $f01.table.rows[0].cells[2] | Should -Be 'Files, SomeFutureInternalScope'
    }
}
