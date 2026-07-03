# PpaStatus.ps1 - the status model (model layer, not presentation).
# The five statuses, validation, per-section counting, and the default at-a-glance
# headline rule. Shared by the assemble stage and the renderer.
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

# The canonical status order used everywhere counts are emitted.
$script:PpaStatusOrder = @('OK', 'Improvement', 'Recommendation', 'Informational', 'Verify manually')

function Get-PpaStatusOrder {
    return $script:PpaStatusOrder
}

function Get-PpaMidDot {
    # The middot separator (U+00B7) the report uses between summary fragments.
    # Returned as a char so source files stay ASCII (Windows PowerShell 5.1); the
    # renderer encodes it to a numeric HTML entity on output.
    return [char]0x00B7
}

function Test-PpaStatus {
    # True if $Status is one of the five allowed values.
    param([string]$Status)
    return ($script:PpaStatusOrder -contains $Status)
}

function Get-PpaSectionCounts {
    # Count a section's findings by status. Returns an ordered hashtable keyed by
    # the five status names. Finding-level status is the only thing that counts
    # (row-level status inside a table is display detail).
    param($Section)
    $c = [ordered]@{ 'OK'=0; 'Improvement'=0; 'Recommendation'=0; 'Informational'=0; 'Verify manually'=0 }
    foreach ($f in @($Section.findings)) {
        if ($null -ne $f -and $c.Contains([string]$f.status)) {
            $c[[string]$f.status] = $c[[string]$f.status] + 1
        }
    }
    return $c
}

function Get-PpaGlanceHeadline {
    # The default at-a-glance dot status for a section, by precedence:
    #   Improvement > Recommendation > OK > Informational > Verify manually.
    # A section may override this explicitly (e.g. Audit stays OK even with a Verify).
    param($Section)
    $counts = Get-PpaSectionCounts $Section
    foreach ($st in @('Improvement', 'Recommendation', 'OK', 'Informational', 'Verify manually')) {
        if ([int]$counts[$st] -gt 0) { return $st }
    }
    return 'Informational'
}
