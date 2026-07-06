# PpaCoverageMatrix.ps1 - renders the CoverageModel (Wave 4 spec 5.1/5.3/5.5-5.8).
# Draw-only: the model comes fully classified from Get-PpaCoverageModel; this file
# adds NO logic beyond presentation. Every tenant-derived string (policy names in
# tooltips) passes the shared render boundary (ConvertTo-PpaHtmlText/Attr), so
# HTML-encoding is unconditional and -Redact/-RedactNames pseudonymize here too.
# None vs Unknown is print-safe by construction: distinct color family PLUS
# hatching PLUS glyph PLUS in-cell text (see the covm-* rules in the shared CSS).
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function Get-PpaCoverageCellStyle {
    param([string]$State)
    switch ($State) {
        'Covered'   { return [pscustomobject]@{ Css = 'covm-covered';  Glyph = '&#10003;' } }
        'Partial'   { return [pscustomobject]@{ Css = 'covm-partial';  Glyph = '&#9680;' } }
        'Test-only' { return [pscustomobject]@{ Css = 'covm-testonly'; Glyph = '&#9675;' } }
        'None'      { return [pscustomobject]@{ Css = 'covm-none';     Glyph = '&#10007;' } }
        'Unknown'   { return [pscustomobject]@{ Css = 'covm-unknown';  Glyph = '?' } }
        'N/A'       { return [pscustomobject]@{ Css = 'covm-na';       Glyph = '&#8211;' } }
        # Defensive default for out-of-enum states; nothing produces one since the
        # Copilot x Retention render-hold was lifted (Wave 5 cleanup Part 1).
        default     { return [pscustomobject]@{ Css = 'covm-held';     Glyph = '&#8212;' } }
    }
}

function Write-PpaCoverageMatrix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Coverage
    )
    if ($null -eq $Coverage) { return '' }

    $sb = New-Object System.Text.StringBuilder

    # Collapsible glanceable header (Wave 5 addendum): the card-header toggles the grid via
    # the shared vanilla collapse handler; collapsed-by-default reclaims vertical space. The
    # one-line coverage tally (assessed cell states) stays visible - aggregate metrics, so
    # safe to show even under redaction. N/A cells are excluded from the tally.
    $stateCounts = [ordered]@{ 'Covered'=0; 'Partial'=0; 'Test-only'=0; 'None'=0; 'Unknown'=0 }
    foreach ($cell in @($Coverage.cells)) {
        $cs = [string]$cell.state
        if ($stateCounts.Contains($cs)) { $stateCounts[$cs] = [int]$stateCounts[$cs] + 1 }
    }
    $labels = @{ 'Covered'='covered'; 'Partial'='partial'; 'Test-only'='test-only'; 'None'='none'; 'Unknown'='unknown' }
    $tallyParts = New-Object System.Collections.Generic.List[string]
    foreach ($k in $stateCounts.Keys) {
        if ([int]$stateCounts[$k] -gt 0) { $tallyParts.Add(([string][int]$stateCounts[$k]) + ' ' + $labels[$k]) }
    }
    $tally = if ($tallyParts.Count -gt 0) { $tallyParts -join ' &middot; ' } else { 'no assessed cells' }

    [void]$sb.AppendLine('  <div class="card mt-3 covm" id="Coveragematrix">')
    [void]$sb.Append('    <div class="card-header sumhead" data-toggle="collapse" data-target="#body-Coveragematrix" role="button" tabindex="0" aria-expanded="false" aria-controls="body-Coveragematrix">')
    [void]$sb.Append('<i class="fas fa-chevron-right chev"></i><strong>Coverage Matrix</strong>')
    [void]$sb.Append('<span class="sum-glance">').Append($tally).AppendLine('</span></div>')
    [void]$sb.AppendLine('    <div class="collapse" id="body-Coveragematrix">')
    [void]$sb.AppendLine('    <div class="card-body">')

    # Degraded-collector banner above the matrix (ruled 5.1).
    if ($Coverage.banner.show) {
        $parts = @($Coverage.banner.degraded | ForEach-Object {
            (ConvertTo-PpaHtmlText (([string]$_.collector) -replace '_', ' ')) + ' (' + (ConvertTo-PpaHtmlText ([string]$_.outcome)) + ')'
        })
        [void]$sb.Append('      <div class="covm-banner">Coverage visibility is degraded for: ').Append(($parts -join ', '))
        [void]$sb.AppendLine('. Affected cells read Unknown and are excluded from gap counts.</div>')
    }

    # ---- the grid ----
    [void]$sb.AppendLine('      <table class="covm-grid">')
    [void]$sb.Append('        <thead><tr><th>Workload</th>')
    foreach ($col in @($Coverage.columns)) {
        [void]$sb.Append('<th>').Append((ConvertTo-PpaHtmlText ([string]$col.label))).Append('</th>')
    }
    [void]$sb.AppendLine('</tr></thead>')
    [void]$sb.AppendLine('        <tbody>')
    foreach ($row in @($Coverage.rows)) {
        [void]$sb.Append('          <tr><th class="covm-row">').Append((ConvertTo-PpaHtmlText ([string]$row.label))).Append('</th>')
        foreach ($col in @($Coverage.columns)) {
            $cell = @($Coverage.cells | Where-Object { $_.row -eq $row.key -and $_.column -eq $col.key })[0]
            $sty = Get-PpaCoverageCellStyle ([string]$cell.state)
            [void]$sb.Append('<td class="covm-cell ').Append($sty.Css).Append('">')

            $title = ''
            if (@($cell.contributors).Count -gt 0) {
                $title = 'Contributing policies: ' + ((@($cell.contributors)) -join ', ')
            }
            elseif ([string]$cell.state -eq 'N/A') { $title = [string]$cell.naReason }
            [void]$sb.Append('<a class="covm-link" href="#finding-').Append((ConvertTo-PpaHtmlAttr ([string]$cell.checkId))).Append('"')
            if (-not [string]::IsNullOrEmpty($title)) {
                [void]$sb.Append(' title="').Append((ConvertTo-PpaHtmlAttr $title)).Append('"')
            }
            [void]$sb.Append('><span class="covm-glyph">').Append($sty.Glyph).Append('</span><span class="covm-text">').Append((ConvertTo-PpaHtmlText ([string]$cell.state))).Append('</span></a>')
            foreach ($r in @($cell.reasons)) {
                [void]$sb.Append('<br><span class="covm-reason">').Append((ConvertTo-PpaHtmlText ([string]$r))).Append('</span>')
            }
            # Provisional-marker legend invariant (Wave 5 cleanup Part 1): the dagger
            # and its explanatory tooltip render if and only if the cell is still
            # documented-only, so no orphaned legend can survive a provenance flip.
            if ([string]$cell.provenance -eq 'documented-only' -and @('Covered', 'Partial', 'Test-only', 'None') -contains [string]$cell.state) {
                [void]$sb.Append('<span class="covm-prov" title="property shape documented but not yet verified on a live tenant.">&#8224;</span>')
            }
            [void]$sb.Append('</td>')
        }
        [void]$sb.AppendLine('</tr>')
    }
    [void]$sb.AppendLine('        </tbody>')
    [void]$sb.AppendLine('      </table>')

    # ---- tenant-level strip: audit, once, never per-row (ruled 5.2 + A addendum) ----
    $audText = switch ([string]$Coverage.auditStrip.state) {
        'On'  { 'On' } 'Off' { 'Off' } default { 'Not observed this run' }
    }
    [void]$sb.Append('      <p class="covm-strip"><strong>Tenant-level:</strong> Unified audit: ').Append((ConvertTo-PpaHtmlText $audText))
    [void]$sb.Append(' &middot; <a href="#finding-').Append((ConvertTo-PpaHtmlAttr ([string]$Coverage.auditStrip.checkId))).AppendLine('">details</a></p>')

    # ---- principal-scoped strip (ruled 5.2): counts + section links ----
    $pparts = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($Coverage.principal)) {
        $txt = '<a href="#' + (ConvertTo-PpaHtmlAttr ([string]$p.sectionId)) + '">' + (ConvertTo-PpaHtmlText ([string]$p.name)) + '</a>: '
        if ($null -ne $p.count) {
            $txt += [string][int]$p.count + ' ' + $(if ([int]$p.count -eq 1) { 'policy' } else { 'policies' })
        }
        else { $txt += (ConvertTo-PpaHtmlText ([string]$p.note)) }
        $pparts.Add($txt)
    }
    [void]$sb.Append('      <p class="covm-strip"><strong>Principal-scoped (no workload cells):</strong> ').Append(($pparts -join ' &middot; ')).AppendLine('</p>')

    # ---- framing notes (ruled 5.1) ----
    [void]$sb.AppendLine('      <p class="covm-foot">Assessed via Security &amp; Compliance PowerShell only. Container labeling for SharePoint and Teams is out of scope for this matrix.</p>')

    [void]$sb.AppendLine('    </div>')
    [void]$sb.AppendLine('    </div>')
    [void]$sb.AppendLine('  </div>')
    return $sb.ToString()
}
