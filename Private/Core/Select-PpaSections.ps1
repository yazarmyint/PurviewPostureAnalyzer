# Select-PpaSections.ps1 - run-profile section filtering (P5). Applied AFTER analysis
# and BEFORE ConvertTo-PpaNormalized, so collectors/analyzers always run identically
# (zero finding-behavior change) while the report body, exec summary counts, and JSON
# export all reflect only the included sections. Shared by the entry script and the
# fixture-driven sample-report tooling. ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function Select-PpaSections {
    # Include, when supplied, means "only these"; exclude then removes from that set.
    # Unknown keys throw (a thin report must be a choice, never a silent typo).
    # Returns the included sections plus the excluded titles for the footer note.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Sections,
        [string[]]$IncludeSection,
        [string[]]$ExcludeSection
    )

    $all      = @($Sections)
    $validIds = @($all | ForEach-Object { [string]$_.id })

    $requested = @(@($IncludeSection) + @($ExcludeSection) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $bad = @($requested | Where-Object { $validIds -notcontains $_ })
    if ($bad.Count -gt 0) {
        throw ("Select-PpaSections: unknown section key(s): {0}. Valid keys: {1}" -f (($bad | Select-Object -Unique) -join ', '), ($validIds -join ', '))
    }

    $included = $all
    if (@($IncludeSection | Where-Object { $_ }).Count -gt 0) {
        $included = @($included | Where-Object { $IncludeSection -contains [string]$_.id })
    }
    if (@($ExcludeSection | Where-Object { $_ }).Count -gt 0) {
        $included = @($included | Where-Object { $ExcludeSection -notcontains [string]$_.id })
    }

    $includedIds = @($included | ForEach-Object { [string]$_.id })
    $excluded    = @($all | Where-Object { $includedIds -notcontains [string]$_.id })

    return [pscustomobject]@{
        Sections       = @($included)
        ExcludedTitles = @($excluded | ForEach-Object { [string]$_.title })
    }
}
