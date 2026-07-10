# PpaHtml.ps1 - rendering helpers for the Purview posture report.
# ASCII-only source (Windows PowerShell 5.1). All non-ASCII output is emitted as
# numeric HTML entities by ConvertTo-PpaHtmlText so the produced HTML is pure ASCII
# and renders identically regardless of how it is served.

Set-StrictMode -Off

# ---------------------------------------------------------------------------
# Encoders
# ---------------------------------------------------------------------------

function ConvertTo-PpaHtmlText {
    # HTML-encode text for element content. Escapes & < > and converts any
    # non-ASCII / control character to a numeric entity. Quotes are left literal
    # (legal in text content and matches the mock).
    # All rendered text flows through here or ConvertTo-PpaHtmlAttr, which makes the
    # pair the display boundary where P6 redaction is applied (no-op when inactive).
    param([AllowNull()][string]$Text)
    $Text = ConvertTo-PpaRedactedText $Text
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int][char]$ch
        if     ($ch -eq '&') { [void]$sb.Append('&amp;') }
        elseif ($ch -eq '<') { [void]$sb.Append('&lt;') }
        elseif ($ch -eq '>') { [void]$sb.Append('&gt;') }
        elseif ($code -ge 32 -and $code -le 126) { [void]$sb.Append($ch) }
        elseif ($ch -eq "`n" -or $ch -eq "`r" -or $ch -eq "`t") { [void]$sb.Append($ch) }
        else { [void]$sb.Append('&#').Append($code).Append(';') }
    }
    return $sb.ToString()
}

function ConvertTo-PpaHtmlAttr {
    # Encode text destined for a double-quoted HTML attribute (e.g. an href).
    # Shares the P6 redaction boundary with ConvertTo-PpaHtmlText.
    param([AllowNull()][string]$Text)
    $Text = ConvertTo-PpaRedactedText $Text
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int][char]$ch
        if     ($ch -eq '&')  { [void]$sb.Append('&amp;') }
        elseif ($ch -eq '<')  { [void]$sb.Append('&lt;') }
        elseif ($ch -eq '>')  { [void]$sb.Append('&gt;') }
        elseif ($ch -eq '"')  { [void]$sb.Append('&quot;') }
        elseif ($code -ge 32 -and $code -le 126) { [void]$sb.Append($ch) }
        else { [void]$sb.Append('&#').Append($code).Append(';') }
    }
    return $sb.ToString()
}

# ---------------------------------------------------------------------------
# Status -> visual mapping (see PLAN.md section 5).
# The status *model* (order, counts, validation) lives in Private/Model/PpaStatus.ps1;
# this file owns only the presentation mapping. $script:PpaStatusOrder is provided by
# PpaStatus.ps1, which must be dot-sourced first.
# ---------------------------------------------------------------------------

function Get-PpaStatusStyle {
    param([string]$Status)
    switch ($Status) {
        'OK'              { return [pscustomobject]@{ Badge='badge-success';   Callout='bd-callout-success';   Dot='ok';     Icon='fas fa-check-circle text-success';  HeaderLabel='OK';            RowWord='OK' } }
        'Improvement'     { return [pscustomobject]@{ Badge='badge-warning';   Callout='bd-callout-warning';   Dot='impr';   Icon='fas fa-times-circle text-danger';   HeaderLabel='Improvement';   RowWord='Improvement' } }
        'Recommendation'  { return [pscustomobject]@{ Badge='badge-info';      Callout='bd-callout-info';      Dot='rec';    Icon='fas fa-info-circle text-muted';     HeaderLabel='Recommendation';RowWord='Recommendation' } }
        'Informational'   { return [pscustomobject]@{ Badge='badge-secondary'; Callout='bd-callout-secondary'; Dot='info';   Icon='';                                  HeaderLabel='Informational'; RowWord='Informational' } }
        'Verify manually' { return [pscustomobject]@{ Badge='badge-dark';      Callout='bd-callout-dark';      Dot='verify'; Icon='fas fa-user-check text-secondary';  HeaderLabel='Verify';        RowWord='Verify manually' } }
        default           { throw "Unknown status: '$Status'" }
    }
}

function Get-PpaRowStatusHtml {
    # The status cell inside a drill-down table row. Informational renders plain
    # text (no icon); every other status gets its icon.
    param([string]$Status)
    $s = Get-PpaStatusStyle $Status
    $word = ConvertTo-PpaHtmlText $s.RowWord
    if ([string]::IsNullOrEmpty($s.Icon)) {
        return '<span class="rowstat">' + $word + '</span>'
    }
    return '<span class="rowstat"><i class="' + $s.Icon + '"></i> ' + $word + '</span>'
}

# ---------------------------------------------------------------------------
# Fragment builders
# ---------------------------------------------------------------------------

function Write-PpaCountBadges {
    # Section-header badges: only non-zero counts, short header labels.
    param($Counts)
    $sb = New-Object System.Text.StringBuilder
    foreach ($st in $script:PpaStatusOrder) {
        $n = [int]$Counts[$st]
        if ($n -gt 0) {
            $sty = Get-PpaStatusStyle $st
            [void]$sb.Append('<span class="badge ').Append($sty.Badge).Append('">').Append($sty.HeaderLabel).Append(' ').Append($n).Append('</span>')
        }
    }
    return $sb.ToString()
}

function Write-PpaSummaryCountCells {
    # Solutions Summary badges: all five counts (including zeros) as fixed-width sscount pills.
    param($Counts)
    $sb = New-Object System.Text.StringBuilder
    foreach ($st in $script:PpaStatusOrder) {
        $sty = Get-PpaStatusStyle $st
        [void]$sb.Append('<span class="badge ').Append($sty.Badge).Append(' sscount">').Append([int]$Counts[$st]).Append('</span>')
    }
    return $sb.ToString()
}

function Write-PpaPostureSummary {
    # Page-one posture summary: run metadata line, severity count tiles, and the
    # top-findings list (every Recommendation, then every Improvement, capped at 15).
    # Counts come from the same section/finding objects the body renders.
    # Titled "Posture Summary" deliberately - a posture snapshot feeding consultant
    # judgment, not a finished consulting deliverable (Wave 3.1 Part A).
    param($Meta, $Sections, $Totals)

    $sb = New-Object System.Text.StringBuilder
    # Collapsible glanceable header (Wave 5 addendum): the card-header toggles the body via
    # the shared vanilla collapse handler; collapsed-by-default reclaims the top of the report.
    # The severity tallies stay visible when collapsed - aggregate posture metrics, so safe to
    # show even under redaction (no tenant-derived strings).
    [void]$sb.AppendLine('  <div class="card mt-3 postsum" id="Posturesummary">')
    [void]$sb.AppendLine('    <div class="card-header sumhead" data-toggle="collapse" data-target="#body-Posturesummary" role="button" tabindex="0" aria-expanded="false" aria-controls="body-Posturesummary">')
    [void]$sb.AppendLine('      <i class="fas fa-chevron-right chev"></i><strong>Posture Summary</strong>')
    $glanceParts = New-Object System.Collections.Generic.List[string]
    $ariaParts   = New-Object System.Collections.Generic.List[string]
    foreach ($st in $script:PpaStatusOrder) {
        $dot = (Get-PpaStatusStyle $st).Dot
        $n   = [int]$Totals[$st]
        $glanceParts.Add('<span class="sg-item"><span class="gdot ' + $dot + '"></span>' + $n + '</span>')
        $ariaParts.Add((ConvertTo-PpaHtmlAttr $st) + ' ' + $n)
    }
    [void]$sb.Append('      <span class="sum-glance" aria-label="').Append(($ariaParts -join ', ')).Append('">')
    [void]$sb.Append(($glanceParts -join '')).AppendLine('</span>')
    [void]$sb.AppendLine('    </div>')
    [void]$sb.AppendLine('    <div class="collapse" id="body-Posturesummary">')
    [void]$sb.AppendLine('    <div class="card-body">')

    # Run metadata line (tenant hint is masked when redaction is active - P6).
    [void]$sb.Append('      <p class="es-meta">').Append((ConvertTo-PpaHtmlText $Meta.reportTitle))
    [void]$sb.Append(' v').Append((ConvertTo-PpaHtmlText $Meta.version))
    [void]$sb.Append(' &middot; ').Append((ConvertTo-PpaHtmlText $Meta.dateDisplay))
    [void]$sb.Append(' &middot; tenant: ').Append((ConvertTo-PpaHtmlText $Meta.tenant)).AppendLine('</p>')

    # Severity count tiles (all five statuses, so the tiles always sum to the body).
    $tileOrder  = @('Recommendation', 'Improvement', 'OK', 'Informational', 'Verify manually')
    $tileLabels = @{ 'Recommendation'='Recommendations'; 'Improvement'='Improvements'; 'OK'='OK'; 'Informational'='Informational'; 'Verify manually'='Verify manually' }
    [void]$sb.AppendLine('      <div class="es-tiles">')
    foreach ($st in $tileOrder) {
        $sty = Get-PpaStatusStyle $st
        [void]$sb.Append('        <div class="es-tile"><span class="badge ').Append($sty.Badge).Append(' es-num">').Append([int]$Totals[$st])
        [void]$sb.Append('</span><div class="es-lbl">').Append((ConvertTo-PpaHtmlText $tileLabels[$st])).AppendLine('</div></div>')
    }
    [void]$sb.AppendLine('      </div>')

    # Top findings: every Recommendation, then every Improvement, in section order.
    $top = New-Object System.Collections.Generic.List[object]
    foreach ($want in @('Recommendation', 'Improvement')) {
        foreach ($sec in @($Sections)) {
            foreach ($f in @($sec.findings)) {
                if ([string]$f.status -eq $want) {
                    $top.Add([pscustomobject]@{ Id = [string]$f.id; Title = [string]$f.title; Section = [string]$sec.title; Status = $want })
                }
            }
        }
    }
    if ($top.Count -eq 0) {
        [void]$sb.AppendLine('      <p class="es-none">No Recommendations or Improvements surfaced by this run.</p>')
    } else {
        [void]$sb.AppendLine('      <h6 class="es-top">Top findings</h6>')
        [void]$sb.AppendLine('      <div class="es-list">')
        $cap = 15
        $shown = if ($top.Count -gt $cap) { $cap } else { $top.Count }
        for ($i = 0; $i -lt $shown; $i++) {
            $t = $top[$i]
            $dot = (Get-PpaStatusStyle $t.Status).Dot
            [void]$sb.Append('        <a class="es-item" data-sev="').Append((ConvertTo-PpaHtmlAttr $t.Status)).Append('" href="#finding-').Append((ConvertTo-PpaHtmlAttr $t.Id)).Append('">')
            [void]$sb.Append('<span class="gdot ').Append($dot).Append('"></span><strong>').Append((ConvertTo-PpaHtmlText $t.Id)).Append('</strong> ')
            [void]$sb.Append((ConvertTo-PpaHtmlText $t.Title)).Append('<span class="es-sec">').Append((ConvertTo-PpaHtmlText $t.Section)).AppendLine('</span></a>')
        }
        if ($top.Count -gt $cap) {
            [void]$sb.Append('        <div class="es-more">+').Append($top.Count - $cap).AppendLine(' more below</div>')
        }
        [void]$sb.AppendLine('      </div>')
    }

    [void]$sb.AppendLine('    </div>')
    [void]$sb.AppendLine('    </div>')
    [void]$sb.AppendLine('  </div>')
    return $sb.ToString()
}

function Write-PpaFilterBar {
    # P2: sticky control bar - one toggle chip per status (all on by default), a
    # case-insensitive substring search over finding cards, and a reset. Interactive
    # only; the P3 print stylesheet hides it.
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('  <div class="filterbar" id="Filterbar">')
    [void]$sb.AppendLine('    <span class="fb-label">Filter:</span>')
    foreach ($st in $script:PpaStatusOrder) {
        $dot = (Get-PpaStatusStyle $st).Dot
        [void]$sb.Append('    <button type="button" class="fb-chip active" data-fb="').Append((ConvertTo-PpaHtmlAttr $st)).Append('">')
        [void]$sb.Append('<span class="gdot ').Append($dot).Append('"></span>').Append((ConvertTo-PpaHtmlText $st)).AppendLine('</button>')
    }
    [void]$sb.AppendLine('    <input type="text" class="fb-search" placeholder="Search findings..." aria-label="Search findings">')
    [void]$sb.AppendLine('    <button type="button" class="fb-reset">Reset</button>')
    [void]$sb.AppendLine('    <span class="fb-status"></span>')
    [void]$sb.AppendLine('  </div>')
    return $sb.ToString()
}

function Write-PpaDetailTable {
    param($Table)
    if ($null -eq $Table) { return '' }
    $cols = @($Table.columns)
    $n = $cols.Count
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('          <table class="table table-sm detail">')
    [void]$sb.Append('            <thead><tr>')
    foreach ($c in $cols) { [void]$sb.Append('<th>').Append((ConvertTo-PpaHtmlText $c)).Append('</th>') }
    [void]$sb.AppendLine('</tr></thead>')
    [void]$sb.AppendLine('            <tbody>')
    foreach ($row in @($Table.rows)) {
        $cells = @($row.cells)
        [void]$sb.Append('              <tr>')
        for ($i = 0; $i -lt $cells.Count; $i++) {
            $raw = [string]$cells[$i]
            # Empty/missing values render as an em dash placeholder, never a blank hole.
            $val = if ([string]::IsNullOrWhiteSpace($raw)) { '&#8212;' } else { ConvertTo-PpaHtmlText $raw }
            if ($i -eq 0 -and $row.indent) { $val = '&nbsp;&nbsp;&#8627; ' + $val }
            [void]$sb.Append('<td>').Append($val).Append('</td>')
        }
        [void]$sb.Append('<td>').Append((Get-PpaRowStatusHtml $row.status)).Append('</td>')
        [void]$sb.AppendLine('</tr>')
        if ($row.remark) {
            [void]$sb.Append('              <tr><td colspan="').Append($n).Append('" class="remarks"><i class="fas fa-info-circle"></i> Remarks: ')
            [void]$sb.Append((ConvertTo-PpaHtmlText ([string]$row.remark))).AppendLine('</td></tr>')
        }
    }
    [void]$sb.AppendLine('            </tbody>')
    [void]$sb.AppendLine('          </table>')
    return $sb.ToString()
}

function Write-PpaRemediation {
    # P7 (reworked in Wave 3.1 B1): collapsible "How to remediate" region inside a
    # finding's drill-down. Native <details> (no Bootstrap collapse, no jQuery):
    # keeps the drill-down collapse count stable and prints via the beforeprint
    # open-all handler. Prose portal guidance + Learn link ONLY - no PowerShell,
    # no code blocks, ever (a cmdlet 'fix' misleads on what remediation involves).
    # Caller gates on status - this renders whatever entry it is given.
    param($Entry)
    if ($null -eq $Entry) { return '' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('          <details class="remed">')
    [void]$sb.AppendLine('            <summary><i class="fas fa-tools"></i> How to remediate</summary>')
    [void]$sb.AppendLine('            <div class="remed-body">')
    # portalPath carries the 2-3 sentence portal-first guidance (or the minimal
    # fallback line for not-grounded checks) - prose, so no label prefix.
    if (-not [string]::IsNullOrEmpty([string]$Entry.portalPath)) {
        [void]$sb.Append('              <p class="remed-portal">').Append((ConvertTo-PpaHtmlText ([string]$Entry.portalPath))).AppendLine('</p>')
    }
    if (-not [string]::IsNullOrEmpty([string]$Entry.learnUrl)) {
        [void]$sb.Append('              <a class="remed-learn" href="').Append((ConvertTo-PpaHtmlAttr ([string]$Entry.learnUrl))).Append('" target="_blank">')
        [void]$sb.AppendLine('<i class="fas fa-external-link-square-alt"></i> Microsoft Learn guidance</a>')
    }
    [void]$sb.AppendLine('              <p class="remed-note">Portal guidance for planning - Microsoft guidance evolves, so confirm against the current Microsoft Learn article before acting. This tool never executes remediation.</p>')
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('          </details>')
    return $sb.ToString()
}

function Write-PpaLearnMore {
    param($Links)
    $items = @($Links)
    if ($items.Count -eq 0) { return '' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('          <div class="learnmore">')
    foreach ($l in $items) {
        $url   = ConvertTo-PpaHtmlAttr ([string]$l.url)
        $label = ConvertTo-PpaHtmlText ([string]$l.label)
        $tag   = ConvertTo-PpaHtmlText ([string]$l.tag)
        [void]$sb.Append('            <a href="').Append($url).Append('" target="_blank"><i class="fas fa-external-link-square-alt"></i> ')
        [void]$sb.Append($label).Append('<span class="lm-tag">').Append($tag).AppendLine('</span></a>')
    }
    [void]$sb.AppendLine('          </div>')
    return $sb.ToString()
}

# ---------------------------------------------------------------------------
# Static document chunks (fixed scaffolding for the shipped report design)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Per-solution section icons (Wave 6 - Mockup A v2 port).
# Rendered as CSS ::before background images keyed on the stable section-card IDs,
# so there is NO body-markup change (zero impact on anchors, data attributes, the
# collapse-toggle count, or any Pester-tested string). Icons are decorative: the
# ::before uses empty content, so they are screen-reader silent, and the selector is
# .seccard-scoped so the Solutions Summary table never receives one. Sections without
# a mapped icon fall back to a neutral glyph. Everything is a self-contained inline
# SVG data URI (offline, ASCII). A data URI background cannot inherit currentColor,
# so the stroke color is baked to the report accent (matches Mockup A v2).
# ---------------------------------------------------------------------------

function Get-PpaSolutionIconSvgMap {
    # Section id -> inline SVG (stroke-only line icon). '_default' is the fallback.
    $c = '#9a6a1e'
    $o = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='$c' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'>"
    return [ordered]@{
        'Sensitivity_Labels'       = "$o<path d='M3.7 12.6 12.1 4.2h7.7v7.7l-8.4 8.4a1.6 1.6 0 0 1-2.3 0L3.7 14.9a1.6 1.6 0 0 1 0-2.3Z'/><circle cx='16' cy='8' r='1.3'/></svg>"
        'Data_Loss_Prevention'     = "$o<path d='M12 3.2 5.4 5.8v5c0 4.2 2.8 6.9 6.6 8.4 3.8-1.5 6.6-4.2 6.6-8.4v-5L12 3.2Z'/><path d='m9.2 11.9 2 2 3.6-3.8'/></svg>"
        'Retention'                = "$o<rect x='3.8' y='4.3' width='16.4' height='4' rx='1'/><path d='M5.4 8.3v10.4a1.4 1.4 0 0 0 1.4 1.4h10.4a1.4 1.4 0 0 0 1.4-1.4V8.3'/><path d='M10 12h4'/></svg>"
        'Insider_Risk'             = "$o<circle cx='9.4' cy='8.2' r='3'/><path d='M3.9 19.3a5.6 5.6 0 0 1 11 0'/><path d='M17.7 12.4 21.1 19h-6.8l3.4-6.6Z'/><path d='M17.7 15v1.4'/></svg>"
        'Audit'                    = "$o<path d='M9 4.2H7.2a2 2 0 0 0-2 2v12.6a2 2 0 0 0 2 2h9.6a2 2 0 0 0 2-2V6.2a2 2 0 0 0-2-2H15'/><rect x='9' y='2.6' width='6' height='3.2' rx='1'/><path d='m8.8 13 2 2 4.4-4.4'/></svg>"
        'eDiscovery'               = "$o<circle cx='10.5' cy='10.5' r='5.8'/><path d='m14.7 14.7 4.6 4.6'/></svg>"
        'Communication_Compliance' = "$o<path d='M20 11.5a7 7 0 0 1-9.9 6.4L4.5 20l1.6-4.2A7 7 0 1 1 20 11.5Z'/><path d='m8.9 11.4 2 2 3.8-3.8'/></svg>"
        'DSPM_for_AI'              = "$o<path d='M11.5 3.8c.6 3.6 1.6 4.6 5.2 5.2-3.6.6-4.6 1.6-5.2 5.2-.6-3.6-1.6-4.6-5.2-5.2 3.6-.6 4.6-1.6 5.2-5.2Z'/><path d='M18.4 13.6c.3 1.6.8 2.1 2.4 2.4-1.6.3-2.1.8-2.4 2.4-.3-1.6-.8-2.1-2.4-2.4 1.6-.3 2.1-.8 2.4-2.4Z'/></svg>"
        '_default'                 = "$o<rect x='4' y='4' width='7' height='7' rx='1.3'/><rect x='13' y='4' width='7' height='7' rx='1.3'/><rect x='4' y='13' width='7' height='7' rx='1.3'/><rect x='13' y='13' width='7' height='7' rx='1.3'/></svg>"
    }
}

function ConvertTo-PpaSvgDataUri {
    # Deterministic, ASCII-safe URL-encoding for an inline SVG inside a CSS url("data:...").
    param([Parameter(Mandatory = $true)][string]$Svg)
    $s = $Svg -replace '"', "'"
    $s = ($s -replace '\s+', ' ').Trim()
    $s = $s.Replace('%', '%25').Replace('#', '%23').Replace('<', '%3C').Replace('>', '%3E').Replace(' ', '%20')
    return 'data:image/svg+xml,' + $s
}

function Get-PpaSolutionIconCss {
    # The ::before icon rules appended to the shared stylesheet. One .seccard-scoped base
    # rule carrying the neutral fallback, then one custom-property override per known
    # section id. Screen-reader silent (empty content); never targets the Solutions Summary.
    $map = Get-PpaSolutionIconSvgMap
    $fallback = ConvertTo-PpaSvgDataUri $map['_default']
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('  /* ---- per-solution section icons (A-v2): decorative CSS ::before, keyed on stable section IDs; .seccard-scoped so the Solutions Summary table is never touched; unmapped sections use the neutral fallback ---- */')
    [void]$sb.Append('  .seccard > .card-header .col-sm > a::before{ content:""; display:inline-block; width:19px; height:19px; margin-right:9px; vertical-align:-4px; background:var(--sec-icon, url("').Append($fallback).AppendLine('")) no-repeat center / contain; }')
    foreach ($id in $map.Keys) {
        if ($id -eq '_default') { continue }
        $uri = ConvertTo-PpaSvgDataUri $map[$id]
        [void]$sb.Append('  #').Append($id).Append('{ --sec-icon:url("').Append($uri).AppendLine('"); }')
    }
    return $sb.ToString()
}

function Get-PpaSharedReportCss {
    # The single shared stylesheet (C-fix 4): consumed by BOTH the main report head
    # and the delta report head, so the two artifacts render as one product family.
    # Never hand-copy these rules into another template.
    #
    # Wave 6 (approved Mockup A v2 port): the enterprise compliance-brief re-skin -
    # wider responsive shell (1680px) with capped prose measure, serif display + humanist
    # sans body, one brass accent, two-column top-findings. Structure unchanged; layers:
    #   1. compat - re-implements the Bootstrap 4 subset the markup uses (grid, card,
    #      badge, table, btn) + a Font Awesome -> monochrome-unicode map, so the report
    #      renders with NO CDN. (No CDN <link>/<script> tags in the head/footer.)
    #   2. tokens (:root) + the tokenized component CSS. The @media print block + covm
    #      gradient patterns are preserved verbatim (Pester asserts those substrings).
    #   3. collapse addendum (.sumhead / .sum-glance) for the collapsible Posture Summary
    #      + Coverage Matrix headers, then the per-solution section icons appended by
    #      Get-PpaSolutionIconCss (decorative CSS ::before, keyed on the section IDs).
    $base = @'
  /* =====================================================================
     PurviewPostureAnalyzer (PPA) report stylesheet - enterprise compliance-brief style (Mockup A v2).
     Editorial: serif display + humanist sans body, warm paper, one brass accent,
     wider responsive shell with capped prose measure. Same markup + hooks as before.
     Layer 1 (compat: grid + FA glyph map + collapse) is preserved so the report
     stays framework-free / offline; layers 2-3 are the tokens + components.
     ===================================================================== */

  /* ---- 1. framework-free compat layer (structural - preserved) ---- */
  *,*::before,*::after{box-sizing:border-box;}
  body{margin:0;font-family:var(--font-sans);line-height:1.5;color:var(--body);}
  img{max-width:100%;height:auto;}
  p{margin:0 0 1rem;}
  .row{display:flex;flex-wrap:wrap;}
  .container-fluid{width:100%;padding-left:12px;padding-right:12px;}
  .navbar{display:flex;flex-wrap:wrap;align-items:center;padding:.5rem 1rem;}
  .col,.col-sm{flex:1 1 0%;min-width:0;}
  .col-auto{flex:0 0 auto;width:auto;}
  .col-sm-10{flex:1 1 auto;min-width:0;}
  .col-sm-2{flex:0 0 auto;margin-left:auto;text-align:right;}
  .col-6{flex:0 0 50%;max-width:50%;padding-left:6px;padding-right:6px;}
  @media (min-width:768px){ .col-md-3{flex:0 0 25%;max-width:25%;} }
  .text-right{text-align:right;} .text-center{text-align:center;}
  .ml-3{margin-left:1rem;} .mt-3{margin-top:1.35rem;} .p-3{padding:1rem;}
  .text-success{color:var(--sev-ok);} .text-danger{color:#b23b2e;}
  .text-muted{color:var(--faint);} .text-secondary{color:var(--sev-verify);}
  .bg-light{background:var(--paper);}
  table{border-collapse:collapse;}
  .table{width:100%;margin-bottom:1rem;}
  .table td,.table th{padding:.5rem .55rem;text-align:left;}
  .table-sm td,.table-sm th{padding:.34rem .45rem;}
  .table-borderless td,.table-borderless th{border:0;}
  .fas,.far,.fa{font-style:normal;display:inline-block;line-height:1;font-family:inherit;}
  .fa-chevron-right::before{content:"\203A";}
  .fa-external-link-square-alt::before{content:"\2197";}
  .fa-tools::before{content:"\2699";}
  .fa-info-circle::before{content:"\2139";}
  .fa-check-circle::before{content:"\2714";}
  .fa-times-circle::before{content:"\2716";}
  .fa-user-check::before{content:"\25CB";}
  .fa-user-cog::before,.fa-shield-alt::before,.fa-archive::before,.fa-user-secret::before,.fa-search::before,.fa-robot::before,.fa-binoculars::before{content:"\25AA";}
  .collapse{display:none;} .collapse.show{display:block;}

  /* ---- 2. design tokens ---- */
  :root{
    --font-serif:Georgia,'Iowan Old Style','Palatino Linotype',Palatino,'Book Antiqua',Cambria,'Times New Roman',serif;
    --font-sans:system-ui,-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;
    --font-mono:ui-monospace,'Cascadia Code','Cascadia Mono',Consolas,'Courier New',monospace;
    --fs-xs:11px; --fs-sm:12.5px; --fs-base:14px; --fs-md:15px; --fs-lg:19px; --fs-xl:24px;
    --ink:#1b2a44; --ink-soft:#2c3c56; --body:#3c4858; --muted:#5c6a7c; --faint:#7c8a9b;
    --paper:#faf7f0; --surface:#ffffff; --surface-1:#f7f3ea; --surface-2:#efe9db; --hover:#faf5e9;
    --hairline:#e8e1d2; --border:#d9d0be;
    --accent:#9a6a1e; --accent-strong:#7c5316; --accent-soft:#f3e9d4;
    --link:#1b527d; --link-strong:#123e60;
    --sev-ok:#1f7a37; --sev-impr:#b4690e; --sev-rec:#0f6a86; --sev-info:#8a94a2; --sev-verify:#56636f;
    --badge-ok-bg:#1f7a37; --badge-ok-fg:#ffffff;
    --badge-impr-bg:#eda93a; --badge-impr-fg:#3a2905;
    --badge-rec-bg:#0f6a86; --badge-rec-fg:#ffffff;
    --badge-info-bg:#6d7889; --badge-info-fg:#ffffff;
    --badge-verify-bg:#39434f; --badge-verify-fg:#ffffff;
    --radius:7px; --radius-sm:4px; --radius-pill:16px;
    --shadow:0 1px 2px rgba(27,42,68,.05),0 8px 26px -18px rgba(27,42,68,.28);
  }

  h2,h5,h6,.card-title,.card-header strong,.card-header a{font-family:var(--font-serif);}
  h2{font-size:var(--fs-xl);font-weight:600;letter-spacing:-.01em;color:var(--ink);margin:0 0 .35rem;line-height:1.15;}
  h5{font-size:1.2rem;font-weight:600;color:var(--ink);margin:0 0 .5rem;}
  h6{font-size:1.02rem;font-weight:600;margin:0 0 .5rem;}
  a{color:var(--link);}
  a:focus-visible,button:focus-visible,input:focus-visible,summary:focus-visible,[tabindex]:focus-visible{
    outline:2px solid var(--accent); outline-offset:2px; border-radius:2px; }

  /* ---- 3. structural chrome ---- */
  .navbar-custom{ background:var(--ink); color:#fff; padding:.7rem 1rem; box-shadow:inset 0 -3px 0 var(--accent); }
  .navbar-custom strong{ font-family:var(--font-serif); font-weight:600; letter-spacing:.01em; font-size:var(--fs-md); }
  .navbar-custom .fa-binoculars::before{ content:"\25C8"; }
  .btn{ display:inline-block;font-weight:600;text-align:center;padding:.4rem .95rem;font-size:var(--fs-sm);line-height:1.4;border:1px solid transparent;border-radius:var(--radius-sm);cursor:pointer;font-family:var(--font-sans); }
  .btn-primary{ color:var(--ink); background:#fff; border-color:rgba(255,255,255,.5); }
  .btn-primary:hover{ background:var(--accent-soft); }

  .app-body{ max-width:1680px; margin:0 auto; padding:1.75rem clamp(16px,3.5vw,52px) 3rem; }
  .card{ position:relative; background:var(--surface); border:1px solid var(--hairline); border-radius:var(--radius); box-shadow:var(--shadow); }
  .card-body{ padding:1.15rem 1.4rem; }
  .card-title{ margin-bottom:.5rem; }
  .card > .card-body > .row > .col > strong:first-of-type{ color:var(--accent-strong); font-family:var(--font-sans); font-weight:700; font-size:var(--fs-sm); text-transform:uppercase; letter-spacing:.06em; }

  /* Card headers: light, serif, ruled - editorial (not a solid blue bar). */
  .card-header{ background:var(--surface); color:var(--ink); padding:.85rem 1.4rem; border-bottom:1px solid var(--hairline); border-radius:var(--radius) var(--radius) 0 0; }
  .card-header strong{ font-size:var(--fs-md); font-weight:600; letter-spacing:.005em; }
  .card-header a{ color:var(--ink); text-decoration:none; }
  .seccard > .card-header{ border-bottom:2px solid var(--ink); }
  .sec-hiddennote{ display:none; font-size:var(--fs-sm); font-weight:400; font-family:var(--font-sans); color:var(--faint); margin-left:10px; }
  .seccard.sec-allhidden .sec-hiddennote{ display:inline; }

  .logo{ max-width:250px; max-height:150px; width:auto; height:auto; }
  .mock-flag{ background:var(--ink); color:#e9e2d2; font-family:var(--font-sans); font-size:var(--fs-sm); letter-spacing:.02em; text-align:center; padding:7px; }
  .redact-flag{ background:#6a1f1f; color:#ffe1e1; font-family:var(--font-sans); font-size:var(--fs-sm); text-align:center; padding:7px; }
  .app-footer{ background:var(--ink); color:#d7dae1; padding:16px 0; font-family:var(--font-sans); font-size:var(--fs-sm); margin-top:2rem; }
  .app-footer .container-fluid{ max-width:1680px; margin:0 auto; }
  .app-footer a{ color:#e7d3ac; }

  /* ---- badges (solid, calm pills) ---- */
  .badge{ display:inline-block;padding:.32em .6em;font-size:var(--fs-xs);font-weight:700;line-height:1;text-align:center;white-space:nowrap;border-radius:var(--radius-pill);vertical-align:baseline;letter-spacing:.02em;font-family:var(--font-sans); }
  .badge-success{ background:var(--badge-ok-bg); color:var(--badge-ok-fg); }
  .badge-warning{ background:var(--badge-impr-bg); color:var(--badge-impr-fg); }
  .badge-info{ background:var(--badge-rec-bg); color:var(--badge-rec-fg); }
  .badge-secondary{ background:var(--badge-info-bg); color:var(--badge-info-fg); }
  .badge-dark{ background:var(--badge-verify-bg); color:var(--badge-verify-fg); }
  .seccard > .card-header .badge{ margin-left:5px; }

  /* ---- severity dots ---- */
  .gdot{ width:9px; height:9px; border-radius:50%; display:inline-block; flex:none; }
  .gdot.ok{ background:var(--sev-ok); } .gdot.impr{ background:var(--sev-impr); } .gdot.rec{ background:var(--sev-rec); }
  .gdot.info{ background:var(--sev-info); } .gdot.verify{ background:var(--sev-verify); }

  /* ---- collapsible summary headers (posture / coverage) ---- */
  .card-header.sumhead{ display:flex; align-items:center; cursor:pointer; background:var(--surface-1); border-bottom:1px solid var(--hairline); }
  .card-header.sumhead:hover{ background:var(--hover); }
  .sumhead .chev{ color:var(--accent); margin-right:9px; width:12px; font-size:1.05rem; }
  .sumhead[aria-expanded="true"] .chev{ transform:rotate(90deg); }
  .sum-glance{ margin-left:auto; display:inline-flex; align-items:center; flex-wrap:wrap; gap:14px; font-size:var(--fs-base); font-weight:600; color:var(--ink-soft); font-family:var(--font-sans); }
  .sum-glance .sg-item{ display:inline-flex; align-items:center; gap:6px; }
  .sum-glance .gdot{ box-shadow:0 0 0 1.5px var(--surface),0 0 0 2.5px rgba(27,42,68,.12); }

  /* ---- EXECUTIVE HERO BAND (injected by A.js; degrades to glance dots) ---- */
  .execband{ margin-top:1.35rem; background:var(--surface); border:1px solid var(--hairline); border-top:3px solid var(--accent); border-radius:var(--radius); box-shadow:var(--shadow); padding:1.2rem 1.4rem 1.35rem; }
  .eb-head{ display:flex; align-items:baseline; justify-content:space-between; flex-wrap:wrap; gap:8px; margin-bottom:.85rem; }
  .eb-kicker{ font-family:var(--font-sans); font-size:var(--fs-xs); font-weight:700; text-transform:uppercase; letter-spacing:.12em; color:var(--accent-strong); }
  .eb-total{ font-family:var(--font-serif); font-size:var(--fs-lg); font-weight:600; color:var(--ink); }
  .eb-total span{ color:var(--faint); font-size:var(--fs-sm); font-family:var(--font-sans); font-weight:600; margin-left:4px; }
  .eb-bar{ display:flex; height:20px; border-radius:5px; overflow:hidden; border:1px solid var(--hairline); background:var(--surface-2); }
  .eb-seg{ min-width:0; }
  .eb-seg.ok{ background:var(--sev-ok); } .eb-seg.impr{ background:var(--sev-impr); } .eb-seg.rec{ background:var(--sev-rec); }
  .eb-seg.info{ background:var(--sev-info); } .eb-seg.verify{ background:var(--sev-verify); }
  .eb-legend{ display:flex; flex-wrap:wrap; gap:8px 20px; margin-top:.85rem; }
  .eb-li{ display:inline-flex; align-items:baseline; gap:7px; font-family:var(--font-sans); font-size:var(--fs-sm); color:var(--muted); }
  .eb-li b{ font-size:var(--fs-md); color:var(--ink); font-weight:700; }
  .eb-li .gdot{ align-self:center; }

  /* ---- posture summary body ---- */
  .es-meta{ color:var(--muted); font-size:var(--fs-base); margin-bottom:.9rem; font-family:var(--font-sans); }
  .es-tiles{ display:flex; flex-wrap:wrap; gap:12px; margin-bottom:1rem; }
  .es-tile{ border:1px solid var(--hairline); border-radius:var(--radius); padding:.7rem 1.15rem; min-width:120px; text-align:center; background:var(--surface-1); }
  .es-num{ font-size:var(--fs-lg); font-weight:800; padding:5px 13px; display:inline-block; border-radius:var(--radius-pill); }
  .es-lbl{ font-size:var(--fs-xs); color:var(--muted); font-weight:700; text-transform:uppercase; letter-spacing:.04em; margin-top:8px; font-family:var(--font-sans); }
  .es-top{ font-family:var(--font-serif); font-size:1.05rem; font-weight:600; color:var(--ink); margin:0 0 .5rem; padding-top:.4rem; border-top:1px solid var(--hairline); }
  .es-list a.es-item{ display:flex; align-items:baseline; gap:9px; padding:5px 0; color:inherit; text-decoration:none; font-size:var(--fs-base); border-bottom:1px solid var(--surface-1); }
  .es-list a.es-item:last-child{ border-bottom:0; }
  .es-list a.es-item:hover{ color:var(--accent-strong); }
  .es-list a.es-item strong{ font-family:var(--font-mono); font-size:var(--fs-sm); color:var(--ink); font-weight:700; }
  .es-list .gdot{ align-self:center; }
  .es-sec{ color:var(--faint); font-size:var(--fs-sm); margin-left:auto; padding-left:12px; white-space:nowrap; font-family:var(--font-sans); }
  .es-more{ color:var(--muted); font-size:var(--fs-sm); padding:6px 0 0 18px; font-style:italic; }
  .es-none{ color:var(--muted); font-size:var(--fs-base); margin:0; }

  /* ---- filter bar (slim, quiet) ---- */
  .filterbar{ position:sticky; top:8px; z-index:100; background:rgba(255,255,255,.94); backdrop-filter:saturate(1.1) blur(3px); border:1px solid var(--hairline); border-radius:var(--radius);
              padding:.5rem .8rem; margin-top:1.35rem; display:flex; flex-wrap:wrap; align-items:center; gap:8px; box-shadow:var(--shadow); }
  .fb-label{ font-size:var(--fs-xs); font-weight:700; color:var(--muted); text-transform:uppercase; letter-spacing:.08em; font-family:var(--font-sans); }
  .fb-chip{ border:1px solid var(--border); background:var(--surface); border-radius:var(--radius-pill); font-size:var(--fs-sm); font-weight:600; color:var(--muted); padding:3px 12px; cursor:pointer; display:inline-flex; align-items:center; gap:7px; font-family:var(--font-sans); }
  .fb-chip:hover{ border-color:var(--accent); }
  .fb-chip.active{ background:var(--accent-soft); border-color:var(--accent); color:var(--accent-strong); }
  .fb-chip:not(.active) .gdot{ opacity:.32; }
  .fb-search{ border:1px solid var(--border); border-radius:var(--radius-sm); font-size:var(--fs-base); padding:5px 11px; min-width:210px; flex:1 1 210px; max-width:330px; font-family:var(--font-sans); }
  .fb-search:focus{ border-color:var(--accent); outline:none; }
  .fb-reset{ border:1px solid var(--border); background:var(--surface); border-radius:var(--radius-sm); font-size:var(--fs-sm); font-weight:600; color:var(--muted); padding:5px 13px; cursor:pointer; font-family:var(--font-sans); }
  .fb-reset:hover{ border-color:var(--accent); color:var(--accent-strong); }
  .fb-status{ font-size:var(--fs-sm); color:var(--faint); margin-left:auto; font-family:var(--font-sans); }
  .finding.fb-hidden{ display:none; }
  .seccard.sec-allhidden .card-body{ display:none; }

  /* ---- environment at a glance ---- */
  .glance .cell{ display:block; border:1px solid var(--hairline); border-radius:var(--radius); padding:.7rem .85rem; height:100%; text-decoration:none; color:inherit; background:var(--surface); transition:border-color .12s ease, box-shadow .12s ease; }
  .glance .cell:hover{ border-color:var(--accent); box-shadow:var(--shadow); }
  .glance .nm{ font-size:var(--fs-sm); color:var(--muted); font-weight:600; display:flex; align-items:center; gap:8px; margin-bottom:5px; font-family:var(--font-sans); }
  .glance .mx{ font-family:var(--font-serif); font-size:var(--fs-xl); font-weight:600; letter-spacing:-.01em; line-height:1.1; color:var(--ink); }
  .glance .sub{ font-size:var(--fs-xs); color:var(--faint); margin-top:2px; font-family:var(--font-sans); }

  /* ---- solutions summary ---- */
  table.summary td{ vertical-align:middle; padding:.42rem .5rem; }
  .sscount{ width:32px; padding:.32rem 0; text-align:center; display:inline-block; margin-left:3px; font-size:var(--fs-sm); border-radius:var(--radius-sm); }
  .ssparent{ background:var(--surface-1); }
  .ssparent td{ font-family:var(--font-serif); font-weight:600; color:var(--ink); letter-spacing:.005em; }
  .sschild a{ color:var(--link); text-decoration:none; }
  .sschild a:hover{ color:var(--link-strong); text-decoration:underline; }

  /* ---- findings ---- */
  .finding{ border-bottom:1px solid var(--hairline); }
  .finding:last-of-type{ border-bottom:0; }
  .finding-head{ cursor:pointer; padding:.75rem .5rem; margin:0; align-items:center; border-radius:var(--radius-sm); }
  .finding-head:hover{ background:var(--hover); }
  .finding-head h6{ margin:0; display:inline; font-weight:600; font-family:var(--font-serif); color:var(--ink); }
  .chev{ color:var(--accent); transition:transform .15s ease; margin-right:11px; width:12px; font-size:1.05rem; }
  .finding-head[aria-expanded="true"] .chev{ transform:rotate(90deg); }
  .finding:target{ background:var(--accent-soft); box-shadow:inset 3px 0 0 var(--accent); }

  .bd-callout{ padding:1rem 1.2rem; margin:.35rem 0 1rem; border:1px solid var(--hairline); border-left-width:4px; border-radius:var(--radius-sm); background:var(--surface-1); }
  .bd-callout-info{ border-left-color:var(--sev-rec); }
  .bd-callout-warning{ border-left-color:var(--sev-impr); }
  .bd-callout-success{ border-left-color:var(--sev-ok); }
  .bd-callout-secondary{ border-left-color:var(--sev-info); }
  .bd-callout-dark{ border-left-color:var(--sev-verify); }
  .whyline{ color:var(--body); margin:.1rem 0 .35rem; font-size:var(--fs-base); }

  table.detail{ font-size:var(--fs-base); margin-top:.7rem; margin-bottom:.25rem; background:var(--surface); border:1px solid var(--hairline); border-radius:var(--radius-sm); overflow:hidden; }
  table.detail thead th{ background:var(--surface-2); border-bottom:2px solid var(--border); font-size:var(--fs-xs); text-transform:uppercase; letter-spacing:.05em; color:var(--muted); padding:.45rem .7rem; font-family:var(--font-sans); }
  table.detail td{ padding:.45rem .7rem; vertical-align:top; border-top:1px solid var(--hairline); }
  table.detail tbody tr:first-child td{ border-top:0; }
  .rowstat{ white-space:nowrap; font-weight:600; font-family:var(--font-sans); font-size:var(--fs-sm); }
  .remarks{ background:var(--surface-2); border:0; color:var(--body); font-size:var(--fs-sm); }
  .remarks i{ color:var(--faint); margin-right:6px; }

  .learnmore{ margin-top:.65rem; padding-top:.5rem; border-top:1px dashed var(--hairline); }
  .learnmore a{ text-decoration:none; display:block; padding:3px 0; color:var(--link); font-size:var(--fs-base); }
  .learnmore a:hover{ color:var(--link-strong); }
  .lm-tag{ font-size:var(--fs-xs); color:var(--faint); text-transform:uppercase; margin-left:7px; letter-spacing:.04em; }
  .anchor-link{ margin-left:9px; color:var(--faint); text-decoration:none; font-weight:700; opacity:0; transition:opacity .12s ease; }
  .finding-head:hover .anchor-link{ opacity:1; }
  .anchor-link:hover{ color:var(--accent); }
  .anchor-link.copied{ color:var(--sev-ok); opacity:1; }
  .backlink a{ color:var(--link); text-decoration:none; font-size:var(--fs-sm); }
  .backlink a:hover{ text-decoration:underline; }

  /* ---- remediation ---- */
  details.remed{ margin-top:.65rem; border-top:1px dashed var(--hairline); padding-top:.5rem; }
  details.remed summary{ cursor:pointer; font-size:var(--fs-base); font-weight:600; color:var(--accent-strong); list-style-position:inside; font-family:var(--font-sans); }
  details.remed summary i{ margin-right:5px; color:var(--accent); }
  .remed-body{ padding:.5rem .1rem .1rem; }
  .remed-portal{ font-size:var(--fs-base); margin-bottom:.5rem; color:var(--body); }
  .remed-learn{ font-size:var(--fs-base); text-decoration:none; display:inline-block; padding:2px 0; color:var(--link); }
  .remed-note{ font-size:var(--fs-sm); color:var(--faint); margin:.45rem 0 0; }

  .profile-note{ color:var(--muted); font-size:var(--fs-sm); margin:1.35rem 2px 0; padding:.55rem .8rem; background:var(--surface-2); border:1px solid var(--hairline); border-radius:var(--radius); font-family:var(--font-sans); }

  /* ---- coverage matrix (None hatching / Unknown dotting preserved) ---- */
  table.covm-grid{ border-collapse:collapse; width:100%; font-size:var(--fs-base); margin-top:.4rem; }
  table.covm-grid thead th{ background:var(--ink); color:#fff; border:1px solid var(--ink); font-size:var(--fs-xs); text-transform:uppercase; letter-spacing:.05em; padding:.5rem .6rem; text-align:center; font-family:var(--font-sans); }
  table.covm-grid th.covm-row{ background:var(--surface-1); border:1px solid var(--border); text-align:left; padding:.5rem .6rem; font-size:var(--fs-sm); color:var(--ink); font-weight:600; width:16%; }
  td.covm-cell{ border:1px solid var(--border); padding:.5rem .6rem; text-align:center; vertical-align:middle; }
  .covm-cell a.covm-link{ text-decoration:none; color:inherit; }
  .covm-glyph{ font-weight:800; margin-right:5px; }
  .covm-text{ font-weight:700; font-size:var(--fs-sm); font-family:var(--font-sans); }
  .covm-covered{ background:#e7f4ea; color:#186a2f; }
  .covm-partial{ background:#fbeecd; color:#7a5410; }
  .covm-testonly{ background:#e8eef6; color:#164e6e; }
  .covm-none{ background:repeating-linear-gradient(45deg,#f7dcd8,#f7dcd8 6px,#ffffff 6px,#ffffff 12px); color:#9a2a22; }
  .covm-unknown{ background:radial-gradient(#cfd6dd 1.3px,#f6f3ec 1.3px); background-size:8px 8px; color:var(--body); }
  .covm-na{ background:var(--surface-1); color:var(--faint); }
  .covm-held{ background:#ffffff; color:var(--faint); }
  .covm-held sup a{ text-decoration:none; color:var(--link); }
  .covm-reason{ display:inline-block; border:1px solid var(--border); border-radius:var(--radius-sm); font-size:10px; padding:0 6px; margin-top:3px; color:var(--muted); background:var(--surface); }
  .covm-prov{ color:#a8781f; margin-left:4px; cursor:help; font-weight:700; }
  .covm-banner{ background:#fbf1d6; border:1px solid var(--sev-impr); border-radius:var(--radius); padding:.5rem .8rem; margin-bottom:.6rem; font-size:var(--fs-base); }
  .covm-strip{ font-size:var(--fs-base); margin:.7rem 0 0; color:var(--ink-soft); }
  .covm-strip a{ color:var(--link); text-decoration:none; }
  .covm-foot{ color:var(--faint); font-size:var(--fs-sm); margin:.5rem 0 0; }

  @media (prefers-reduced-motion:reduce){ .chev{ transition:none; } .glance .cell{ transition:none; } }

  /* ---- print / PDF (asserted substrings kept verbatim; brief adds around them) ---- */
  /* ---- v2 additions: wider shell alignment, readable prose measure, per-section solution icons ---- */
  .navbar-custom .container-fluid{ max-width:1680px; margin:0 auto; }
  .card-body .col > p{ max-width:82ch; }
  .bd-callout p{ max-width:82ch; }
  .es-list{ display:grid; grid-template-columns:1fr; gap:0 34px; }
  @media (min-width:920px){ .es-list{ grid-template-columns:1fr 1fr; } }
  .es-list .es-more{ grid-column:1 / -1; }
  .seccard > .card-header .col-sm > a{ font-size:1.08rem; font-weight:600; letter-spacing:.005em; }
  @media print{
    *{ print-color-adjust:exact; -webkit-print-color-adjust:exact; }
    body{ background:#fff; font-size:11.5pt; }
    .app-body{ max-width:none; margin:0; padding:0; }
    .navbar-custom .container-fluid, .app-footer .container-fluid{ max-width:none; }
    .filterbar, .anchor-link, .backlink, .navbar-custom .btn, .mock-flag, .chev{ display:none !important; }
    .collapse{ display:block !important; height:auto !important; }
    .card{ box-shadow:none; border:1px solid #d7cfbe; }
    .execband{ break-inside:avoid; page-break-inside:avoid; }
    .postsum{ break-after:page; page-break-after:always; }
    .seccard{ break-before:page; page-break-before:always; }
    .finding, .glance .cell, .bd-callout{ break-inside:avoid; page-break-inside:avoid; }
    .finding-head{ cursor:default; }
    .card-header.sumhead{ cursor:default; }
  }
'@
    return $base + (Get-PpaSolutionIconCss)
}

function Get-PpaHtmlHead {
    # Shared document head (C-fix 4): doctype, the shared stylesheet plus optional
    # artifact-specific extra CSS, the title, and the opening body tag. Both the main
    # report and the delta report build their head here.
    # Wave 5: framework-free / offline - NO CDN <link>s. The shared stylesheet re-implements
    # the Bootstrap subset + a Font Awesome -> unicode map, so the report is self-contained.
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$ExtraCss = ''
    )
    $css = Get-PpaSharedReportCss
    if (-not [string]::IsNullOrEmpty($ExtraCss)) { $css = $css + "`n" + $ExtraCss }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!doctype html>')
    [void]$sb.AppendLine('<html lang="en">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('<meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">')
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine($css)
    [void]$sb.AppendLine('</style>')
    [void]$sb.Append('<title>').Append($Title).AppendLine('</title>')
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body class="app bg-light">')
    return $sb.ToString()
}

function Get-PpaReportHead {
    # The main report head - composed from the shared asset (C-fix 4).
    return Get-PpaHtmlHead -Title 'PurviewPostureAnalyzer (PPA)'
}

function Get-PpaNavbarHtml {
@'
<nav class="navbar navbar-custom">
  <div class="container-fluid">
    <div class="col-sm" style="text-align:left"><div class="row"><div><i class="fas fa-binoculars"></i></div>
      <div class="ml-3"><strong>PurviewPostureAnalyzer (PPA)</strong></div></div></div>
    <div class="col-sm" style="text-align:right"><button type="button" class="btn btn-primary" onclick="window.print();">Print</button></div>
  </div>
</nav>
'@
}

function Get-PpaPolishScript {
    # Wave 3 interactive behaviors: vanilla JS, inline, no dependencies. Emitted once
    # before the footer. Progressive enhancement - the Solutions Summary and every finding's
    # title and status read without scripting; expanding a finding's drill-down detail (and
    # the collapsible summary bodies) on screen needs scripting, or print the report to see
    # it all - the print stylesheet forces every collapsed section open.
@'
<script>
(function () {
  'use strict';
  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) { navigator.clipboard.writeText(text); return; }
    var ta = document.createElement('textarea');
    ta.value = text; ta.setAttribute('readonly', '');
    ta.style.position = 'absolute'; ta.style.left = '-9999px';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); } catch (e) { }
    document.body.removeChild(ta);
  }
  // Per-finding anchor: copy the deep link; stop the click reaching the collapse toggle.
  document.addEventListener('click', function (ev) {
    var t = ev.target;
    var a = (t && t.closest) ? t.closest('.anchor-link') : null;
    if (!a) { return; }
    ev.stopPropagation();
    copyText(location.href.split('#')[0] + a.getAttribute('href'));
    a.classList.add('copied');
    setTimeout(function () { a.classList.remove('copied'); }, 1200);
  }, true);

  // Vanilla collapse (Wave 5, replaces Bootstrap): a click on any collapse toggle
  // (finding drill-down heads + the Posture Summary / Coverage Matrix headers) shows or
  // hides its data-target and flips aria-expanded. Matched via [data-target] so the toggle
  // markup stays the single source of the collapse-toggle count (this handler adds none).
  document.addEventListener('click', function (ev) {
    var t = ev.target;
    if (t.closest && t.closest('.anchor-link')) { return; }
    var h = (t && t.closest) ? t.closest('[data-target]') : null;
    if (!h) { return; }
    var sel = h.getAttribute('data-target');
    if (!sel) { return; }
    var body = document.querySelector(sel);
    if (!body) { return; }
    var open = body.classList.toggle('show');
    h.setAttribute('aria-expanded', open ? 'true' : 'false');
  });

  // Keyboard toggle (Enter/Space) for focusable collapse headers (the summary sections).
  document.addEventListener('keydown', function (ev) {
    if (ev.key !== 'Enter' && ev.key !== ' ' && ev.key !== 'Spacebar') { return; }
    var h = (ev.target && ev.target.closest) ? ev.target.closest('[data-target]') : null;
    if (!h || !h.hasAttribute('tabindex')) { return; }
    ev.preventDefault();
    h.click();
  });

  // Auto-expand on anchor: a deep link to a finding, the Posture Summary, or the Coverage
  // Matrix opens the relevant collapse so the target never lands on an empty-looking section.
  function expandForHash() {
    var id = (location.hash || '').slice(1);
    if (!id) { return; }
    var el = document.getElementById(id);
    if (!el) { return; }
    var head = el.classList.contains('finding')
      ? el.querySelector('.finding-head[data-target]')
      : el.querySelector('.card-header.sumhead[data-target]');
    if (!head) { return; }
    var sel = head.getAttribute('data-target');
    var body = sel && document.querySelector(sel);
    if (body && !body.classList.contains('show')) {
      body.classList.add('show');
      head.setAttribute('aria-expanded', 'true');
    }
    el.scrollIntoView({ block: 'start' });
  }
  window.addEventListener('hashchange', expandForHash);

  // P2 severity filter + text search. Hides finding cards only (never touches the
  // collapse elements, so drill-down open state survives filtering).
  var bar = document.getElementById('Filterbar');
  if (bar) {
    var chips = [].slice.call(bar.querySelectorAll('.fb-chip'));
    var search = bar.querySelector('.fb-search');
    var reset = bar.querySelector('.fb-reset');
    var statusEl = bar.querySelector('.fb-status');
    var items = [].slice.call(document.querySelectorAll('.finding')).map(function (el) {
      return { el: el, status: el.getAttribute('data-status') || '', text: (el.textContent || '').toLowerCase() };
    });
    var sections = [].slice.call(document.querySelectorAll('.seccard'));
    var applyFilter = function () {
      var active = {};
      chips.forEach(function (c) { if (c.classList.contains('active')) { active[c.getAttribute('data-fb')] = true; } });
      var q = (search.value || '').toLowerCase().trim();
      var shown = 0;
      items.forEach(function (it) {
        var ok = !!active[it.status] && (q === '' || it.text.indexOf(q) !== -1);
        it.el.classList.toggle('fb-hidden', !ok);
        if (ok) { shown++; }
      });
      // A fully-filtered section collapses to its header with a note, never vanishes.
      sections.forEach(function (sec) {
        var fs = [].slice.call(sec.querySelectorAll('.finding'));
        var hidden = fs.filter(function (f) { return f.classList.contains('fb-hidden'); }).length;
        var all = fs.length > 0 && hidden === fs.length;
        sec.classList.toggle('sec-allhidden', all);
        var note = sec.querySelector('.sec-hiddennote');
        if (note) { note.textContent = all ? '(' + hidden + ' finding' + (hidden === 1 ? '' : 's') + ' hidden by filter)' : ''; }
      });
      var isDefault = q === '' && chips.every(function (c) { return c.classList.contains('active'); });
      statusEl.textContent = isDefault ? '' : shown + ' of ' + items.length + ' findings shown';
    };
    chips.forEach(function (c) { c.addEventListener('click', function () { c.classList.toggle('active'); applyFilter(); }); });
    var debounce = null;
    search.addEventListener('input', function () { if (debounce) { clearTimeout(debounce); } debounce = setTimeout(applyFilter, 120); });
    reset.addEventListener('click', function () { chips.forEach(function (c) { c.classList.add('active'); }); search.value = ''; applyFilter(); });
  }

  // P3 print: expand every drill-down before printing, restore afterwards. The
  // @media print .collapse rule remains as a CSS fallback.
  var printOpened = [];
  window.addEventListener('beforeprint', function () {
    printOpened = [];
    [].slice.call(document.querySelectorAll('.collapse:not(.show)')).forEach(function (el) {
      el.classList.add('show'); printOpened.push(el);
    });
    [].slice.call(document.querySelectorAll('details:not([open])')).forEach(function (el) {
      el.setAttribute('open', ''); el.setAttribute('data-print-opened', '');
    });
  });
  window.addEventListener('afterprint', function () {
    printOpened.forEach(function (el) { el.classList.remove('show'); });
    printOpened = [];
    [].slice.call(document.querySelectorAll('details[data-print-opened]')).forEach(function (el) {
      el.removeAttribute('open'); el.removeAttribute('data-print-opened');
    });
  });

  expandForHash();
})();

  // Posture-at-a-glance band (A-v2 port): additive, vanilla, safe to fail.
/* Posture-at-a-glance band (A-v2 port). Progressive enhancement: builds a severity
   distribution band from the counts already present in the Posture Summary
   header (.sum-glance). Adds NO new content - only re-encodes existing counts and
   the report's own severity labels. No data-target, unique id, degrades to the
   glance dots if scripting is off. */
(function () {
  'use strict';
  function build() {
    var host = document.getElementById('Posturesummary');
    if (!host || document.getElementById('ppa-execband')) { return; }
    var items = host.querySelectorAll('.sum-glance .sg-item');
    if (!items.length) { return; }
    var order  = ['rec', 'impr', 'ok', 'info', 'verify'];
    var known  = ['ok', 'impr', 'rec', 'info', 'verify'];
    var labels = { ok: 'OK', impr: 'Improvements', rec: 'Recommendations', info: 'Informational', verify: 'Verify manually' };
    var counts = {}, total = 0;
    for (var i = 0; i < items.length; i++) {
      var dot = items[i].querySelector('.gdot');
      if (!dot) { continue; }
      var cls = known.filter(function (c) { return dot.classList.contains(c); })[0];
      if (!cls) { continue; }
      var n = parseInt((items[i].textContent || '').replace(/[^0-9]/g, ''), 10) || 0;
      counts[cls] = n; total += n;
    }
    if (total <= 0) { return; }

    var bar = '<div class="eb-bar" role="img" aria-label="Severity distribution of findings">';
    var legend = '<div class="eb-legend">';
    for (var j = 0; j < order.length; j++) {
      var c = order[j], v = counts[c] || 0;
      if (v > 0) { bar += '<span class="eb-seg ' + c + '" style="flex-grow:' + v + ';min-width:6px" title="' + labels[c] + ': ' + v + '"></span>'; }
      legend += '<span class="eb-li"><span class="gdot ' + c + '"></span><b>' + v + '</b> ' + labels[c] + '</span>';
    }
    bar += '</div>'; legend += '</div>';

    var band = document.createElement('section');
    band.id = 'ppa-execband';
    band.className = 'execband';
    band.setAttribute('aria-label', 'Posture at a glance');
    band.innerHTML =
      '<div class="eb-head"><span class="eb-kicker">Posture at a glance</span>' +
      '<span class="eb-total">' + total + ' <span>findings</span></span></div>' + bar + legend;
    host.parentNode.insertBefore(band, host);
  }
  if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', build); } else { build(); }
})();
</script>
'@
}

function Get-PpaFooterHtml {
    # Wave 5: framework-free / offline - the CDN jQuery/Popper/Bootstrap <script> tags are
    # gone; all interactivity is the vanilla JS in Get-PpaPolishScript (incl. collapse).
@'
<footer class="app-footer"><div class="container-fluid">
  <strong>PurviewPostureAnalyzer (PPA) &middot; read-only.</strong> Based on OfficeDev/CAMP (Configuration Analyzer for Microsoft Purview). Reads configuration metadata only &mdash; no document, email or prompt content, no matched values.
  Does not create, modify or delete tenant configuration. Statuses are inputs to user judgment, not compliance determinations,
  and are not mapped to any regulatory framework.
</div></footer>
</body>
</html>
'@
}
