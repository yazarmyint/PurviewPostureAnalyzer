# PpaNormalize.ps1 - the collector-side normalize contract (Wave 4 Part A).
# Three rules every collector output obeys, pinned by Tests\Collect.Contract.Tests.ps1:
#   1. Every leaf is string / number / boolean / null (PS 5.1 serializes enums as
#      integers and dates in invariant-culture format, so anything non-primitive is
#      stringified HERE, never at the snapshot writer).
#   2. DateTime values become ISO-8601 UTC strings at normalize time.
#   3. Session artifacts from remoting never survive into normalized objects.
# Also home to the per-collector outcome enum resolver (spec A.4):
#   Populated | Empty | Partial | AccessDenied | CmdletUnavailable | Failed
#   | Skipped | NotRun
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function ConvertTo-PpaIso8601 {
    # DateTime -> ISO-8601 UTC string ('yyyy-MM-ddTHH:mm:ssZ'). Strings pass through
    # untouched so fixture dates and live string-typed dates agree. Null and the
    # DateTime.MinValue placeholder (what EXO returns for "never") become '' so a
    # policy is never reported as "in test mode since 01-Jan-0001".
    # Kind-unspecified values are treated as local time, matching how PowerShell
    # remoting deserializes DateTimes.
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) {
        if ($Value -eq [datetime]::MinValue) { return '' }
        return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return [string]$Value
}

function Get-PpaOptionalGuid {
    # A.5 opportunistic Guid capture: project the raw object's Guid when the cmdlet
    # provides one, so the snapshot keying rule (Guid -> Identity -> Name) and the
    # delta rename-reconciliation pass can operate. Property-presence check only -
    # no new reads, no new cmdlets. Provenance: documented-only (the Guid property
    # is documented on these cmdlets but not on the live-verified list).
    # Returns '' when the property is absent, null, or the all-zeros placeholder,
    # letting the keying rule fall back to Name.
    param($Object)
    if ($null -eq $Object) { return '' }
    if ($Object.PSObject.Properties.Name -notcontains 'Guid') { return '' }
    $g = [string]$Object.Guid
    if ([string]::IsNullOrEmpty($g) -or $g -eq '00000000-0000-0000-0000-000000000000') { return '' }
    return $g
}

function Get-PpaSessionArtifactNames {
    # Property names PowerShell remoting stamps on deserialized objects. Generic
    # projections (ones that copy every property) must skip these; explicit
    # projections never pick them up in the first place.
    return @('RunspaceId', 'PSComputerName', 'PSShowComputerName', 'PSSourceJobInstanceId', 'PSJobTypeName')
}

function Resolve-PpaCollectorOutcome {
    # Derive the per-collector outcome from the statuses of every read the collector
    # performed (Invoke-PpaReadCmdlet statuses: Ok | AccessDenied | CommandNotFound |
    # Error | Blocked) plus the number of normalized items produced.
    #   all reads Ok             -> Populated (items > 0) / Empty (zero items)
    #   some Ok, some failed     -> Partial (visibility degraded, data incomplete)
    #   no read Ok               -> the most actionable uniform cause, by precedence:
    #                               AccessDenied (fix roles) > CmdletUnavailable
    #                               (fix module/connection) > Failed (investigate)
    # Skipped / NotRun belong to the orchestration layer (a collector that actually
    # ran never reports them); they are stamped when a section is not selected.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ReadStatuses,
        [int]$ItemCount = 0
    )
    $statuses = @($ReadStatuses)
    if ($statuses.Count -eq 0) { return 'Failed' }
    $okCount = @($statuses | Where-Object { $_ -eq 'Ok' }).Count
    if ($okCount -eq $statuses.Count) {
        if ($ItemCount -gt 0) { return 'Populated' }
        return 'Empty'
    }
    if ($okCount -gt 0) { return 'Partial' }
    if ($statuses -contains 'AccessDenied') { return 'AccessDenied' }
    if ($statuses -contains 'CommandNotFound') { return 'CmdletUnavailable' }
    return 'Failed'
}
