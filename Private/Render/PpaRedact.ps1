# PpaRedact.ps1 - render-time redaction (P6). One redaction function applied at the
# display boundary: both HTML encoders (ConvertTo-PpaHtmlText / ConvertTo-PpaHtmlAttr)
# call ConvertTo-PpaRedactedText before encoding, so coverage is consistent and
# testable. Finding data in memory and the JSON export are never touched.
#
# Default -Redact scope: UPNs/email addresses -> user01@[redacted]; *.onmicrosoft.com
# domains and any domain carrying the tenant's own base label (seeded from the meta
# tenant hint and operator) -> [redacted-domain-01]. Tokens are stable per unique
# value within a run so the report stays internally consistent. Microsoft Learn /
# portal URLs never match (only seeded tenant domains and onmicrosoft.com patterns).
#
# Stricter -RedactNames additionally pseudonymizes policy/label names (harvested from
# drill-down tables whose first column header names a Policy or Label) as Policy-01 /
# Label-01 tokens, replaced longest-first everywhere the name appears - including
# remarks and remediation snippet text.
#
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

$script:PpaRedactState = $null

function Initialize-PpaRedaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Normalized,
        [switch]$RedactNames
    )

    $state = @{
        RedactNames = [bool]$RedactNames
        UserMap     = @{}
        DomainMap   = @{}
        NameMap     = @{}
        NameList    = @()
        PolicyCount = 0
        LabelCount  = 0
        BaseLabels  = @()
    }

    # Seed the tenant's own domain base labels from the meta header (tenant hint and
    # operator UPN). Only domains derived from these seeds - plus any *.onmicrosoft.com
    # string - are masked; unrelated domains (learn.microsoft.com) are left alone.
    $seedDomains = New-Object System.Collections.Generic.List[string]
    foreach ($seed in @([string]$Normalized.meta.tenant, [string]$Normalized.meta.operator, [string]$Normalized.meta.organization)) {
        if ([string]::IsNullOrWhiteSpace($seed)) { continue }
        foreach ($m in [regex]::Matches($seed, '@([A-Za-z0-9.-]+\.[A-Za-z]{2,})')) { $seedDomains.Add($m.Groups[1].Value) }
        foreach ($m in [regex]::Matches($seed, '\b([A-Za-z0-9-]+\.onmicrosoft\.com)\b')) { $seedDomains.Add($m.Groups[1].Value) }
        if ($seed -match '^\s*([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)\s*$') { $seedDomains.Add($Matches[1]) }
    }
    $state.BaseLabels = @($seedDomains | ForEach-Object { ([string]$_ -split '\.')[0].ToLower() } |
        Where-Object { $_ -and $_.Length -ge 3 } | Select-Object -Unique)

    # Harvest policy/label names for -RedactNames from the same finding objects the
    # body renders: first-column cells of tables whose first header names the kind.
    if ($RedactNames) {
        foreach ($sec in @($Normalized.sections)) {
            foreach ($f in @($sec.findings)) {
                if ($null -eq $f -or $null -eq $f.table) { continue }
                $cols = @($f.table.columns)
                if ($cols.Count -eq 0) { continue }
                $head = [string]$cols[0]
                $kind = if ($head -match '(?i)policy') { 'Policy' } elseif ($head -match '(?i)label') { 'Label' } else { $null }
                if (-not $kind) { continue }
                foreach ($row in @($f.table.rows)) {
                    $name = [string](@($row.cells)[0])
                    if ([string]::IsNullOrWhiteSpace($name) -or $name.Trim().Length -lt 3) { continue }
                    $name = $name.Trim()
                    $key  = $name.ToLower()
                    if ($state.NameMap.ContainsKey($key)) { continue }
                    if ($kind -eq 'Policy') { $state.PolicyCount++; $token = 'Policy-{0:00}' -f $state.PolicyCount }
                    else                    { $state.LabelCount++;  $token = 'Label-{0:00}'  -f $state.LabelCount }
                    $state.NameMap[$key] = [pscustomobject]@{ Name = $name; Token = $token }
                }
            }
        }
        # Longest-first so 'General - 3yr' is consumed before the label 'General'.
        $state.NameList = @($state.NameMap.Values | Sort-Object { $_.Name.Length } -Descending)
    }

    $script:PpaRedactState = $state
}

function Clear-PpaRedaction {
    $script:PpaRedactState = $null
}

function ConvertTo-PpaRedactedText {
    # The single redaction function. Pass-through when redaction is not active.
    param([AllowNull()][string]$Text)
    $state = $script:PpaRedactState
    if ($null -eq $state -or [string]::IsNullOrEmpty($Text)) { return $Text }

    # 1. UPNs / email addresses (before domains, so the address is tokenized whole).
    $Text = [regex]::Replace($Text, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', {
        param($m)
        $s = $script:PpaRedactState
        $k = $m.Value.ToLower()
        if (-not $s.UserMap.ContainsKey($k)) { $s.UserMap[$k] = ('user{0:00}@[redacted]' -f ($s.UserMap.Count + 1)) }
        $s.UserMap[$k]
    })

    # 2. Tenant domains: every *.onmicrosoft.com, plus any domain whose labels include
    #    a seeded tenant base label (contoso.com, contoso.sharepoint.com, ...).
    $domainEval = {
        param($m)
        $s = $script:PpaRedactState
        $k = $m.Value.ToLower()
        if (-not $s.DomainMap.ContainsKey($k)) { $s.DomainMap[$k] = ('[redacted-domain-{0:00}]' -f ($s.DomainMap.Count + 1)) }
        $s.DomainMap[$k]
    }
    $Text = [regex]::Replace($Text, '\b[A-Za-z0-9-]+\.onmicrosoft\.com\b', $domainEval)
    foreach ($base in $state.BaseLabels) {
        $pattern = '\b(?:[A-Za-z0-9-]+\.)*' + [regex]::Escape($base) + '(?:\.[A-Za-z0-9-]+)+\b'
        $Text = [regex]::Replace($Text, $pattern, $domainEval, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    # 3. Policy/label names (stricter -RedactNames only), longest-first, everywhere.
    if ($state.RedactNames) {
        foreach ($entry in $state.NameList) {
            $pattern = '\b' + [regex]::Escape($entry.Name) + '\b'
            $Text = [regex]::Replace($Text, $pattern, $entry.Token, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }

    return $Text
}
