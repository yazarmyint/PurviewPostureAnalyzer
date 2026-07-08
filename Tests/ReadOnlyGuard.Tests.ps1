# ReadOnlyGuard.Tests.ps1 - the non-negotiable guardrail: collectors and analyzers
# must call read-only Get-* cmdlets only. This test fails the build if a mutating verb
# appears in the tenant-facing surface (Private/Collect, Private/Analyze, Public), with
# a small allow-list for local file / object / model-factory operations.
# Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot

    # Local, non-tenant operations that use a "mutating" verb but are safe.
    $script:PpaGuardAllow = @(
        'New-Object', 'New-Item', 'New-Variable', 'New-Guid', 'New-TimeSpan',
        'Set-Content', 'Set-Variable', 'Set-StrictMode', 'Set-Location',
        'Add-Content', 'Add-Member', 'Add-Type',
        'Clear-PpaRedaction'   # in-memory render redaction state - exact name, never a prefix (B-fix 2)
    )

    # Verbs that indicate a state change on the tenant when applied to a Purview/EXO/Graph noun.
    $script:PpaMutatingVerbs = 'Set|New|Remove|Enable|Disable|Update|Add|Start|Stop|Clear|Reset|Register|Unregister|Restore|Move|Rename|Grant|Revoke|Suspend|Resume|Install|Uninstall|Send'

    function Get-PpaMutatingReference {
        # Return the disallowed mutating cmdlet tokens found in a block of code.
        param([string]$Content)
        $found = New-Object System.Collections.Generic.List[string]
        foreach ($m in [regex]::Matches($Content, "\b(?:$script:PpaMutatingVerbs)-[A-Za-z][A-Za-z0-9]*")) {
            $cmd = $m.Value
            if ($script:PpaGuardAllow -contains $cmd) { continue }
            if ($cmd -match '^(New|Set|Get|Remove|Test|Write|Convert|Export|Import)-Ppa') { continue }  # our own functions
            $found.Add($cmd)
        }
        return $found.ToArray()
    }

    function Remove-PpaLineComments {
        # Strip #-to-end-of-line comments so a comment mentioning a cmdlet name does not
        # trip the scan. (Collector/analyzer code has no '#' inside string literals.)
        param([string]$Content)
        return ($Content -replace '(?m)#.*$', '')
    }
}

Describe 'Read-only guard - detection logic' {
    It 'flags a mutating tenant cmdlet (Set-)' {
        (Get-PpaMutatingReference 'Set-DlpCompliancePolicy -Identity x -Mode Enforce').Count | Should -BeGreaterThan 0
    }
    It 'flags New-/Remove-/Enable- tenant cmdlets' {
        (Get-PpaMutatingReference 'New-RetentionCompliancePolicy;  Remove-Label;  Enable-OrganizationCustomization').Count | Should -Be 3
    }
    It 'allows Get-* reads and local New-Object / New-Item / New-PpaFinding' {
        $safe = 'Get-DlpCompliancePolicy | ForEach-Object { $_ }; New-Object System.Text.StringBuilder; New-Item -ItemType Directory x; New-PpaFinding -Id A -Status OK'
        (Get-PpaMutatingReference $safe).Count | Should -Be 0
    }
    It 'allows Set-Content / Set-StrictMode' {
        (Get-PpaMutatingReference 'Set-StrictMode -Off; Set-Content -Path x -Value y').Count | Should -Be 0
    }
    It 'allows exactly Clear-PpaRedaction but flags any other Clear-Ppa* (no prefix entries)' {
        (Get-PpaMutatingReference 'Clear-PpaRedaction').Count | Should -Be 0
        (Get-PpaMutatingReference 'Clear-PpaMailbox -Identity x').Count | Should -Be 1
    }
}

Describe 'Read-only guard - tenant-facing surface' {
    It 'has no mutating cmdlets anywhere in Private or Public (Wave 4: whole tree)' {
        # Wave 4 extended the scan from Collect/Analyze/Public to ALL of Private so
        # the snapshot writer/loader (Private\Model) and every future file is covered.
        $scanDirs = @('Private', 'Public') |
            ForEach-Object { Join-Path $script:RepoRoot $_ } |
            Where-Object { Test-Path -LiteralPath $_ }

        $violations = New-Object System.Collections.Generic.List[string]
        foreach ($dir in $scanDirs) {
            foreach ($file in Get-ChildItem -LiteralPath $dir -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue) {
                $code = Remove-PpaLineComments ([System.IO.File]::ReadAllText($file.FullName))
                foreach ($hit in (Get-PpaMutatingReference $code)) {
                    $violations.Add(("{0}: {1}" -f $file.Name, $hit))
                }
            }
        }
        $violations -join "`n" | Should -BeNullOrEmpty
    }
}
