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
    param([AllowNull()][string]$Text)
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
    param([AllowNull()][string]$Text)
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

function Write-PpaExecSummary {
    # Page-one executive summary: run metadata line, severity count tiles, and the
    # top-findings list (every Recommendation, then every Improvement, capped at 15).
    # Counts come from the same section/finding objects the body renders.
    param($Meta, $Sections, $Totals)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('  <div class="card mt-3 execsum" id="Execsummary">')
    [void]$sb.AppendLine('    <div class="card-header"><strong>Executive Summary</strong></div>')
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
# Static document chunks (verbatim from posture-report-mock-v5.html; CDN assets)
# ---------------------------------------------------------------------------

function Get-PpaReportHead {
@'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.11.2/css/all.min.css" crossorigin="anonymous">
<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/css/bootstrap.min.css" integrity="sha384-ggOyR0iXCbMQv3Xipma34MD+dH/1fQ784/j6cY/iJTQUOhcWr7x9JvoRxT2MZw1T" crossorigin="anonymous">
<style>
  .navbar-custom{ background-color:#005494; color:white; padding-bottom:10px; }
  .card-header{ background-color:#0078D4; color:white; }
  .card-header a{ color:white; text-decoration:none; }
  .bd-callout{ padding:1rem 1.25rem; margin:.5rem 0 1rem; border:1px solid #eee; border-left-width:.25rem; border-radius:.25rem; background:#fff; }
  .bd-callout-info{ border-left-color:#5bc0de; }
  .bd-callout-warning{ border-left-color:#f0ad4e; }
  .bd-callout-success{ border-left-color:#00bd19; }
  .bd-callout-secondary{ border-left-color:#adb5bd; }
  .bd-callout-dark{ border-left-color:#6c757d; }
  .app-footer{ background-color:#005494; color:white; padding:12px 0; }
  .app-footer a{ color:#cfe6ff; }
  .logo-ph{ width:250px; height:150px; border:1px dashed #b7c6d6; border-radius:4px; color:#8aa0b5; display:flex; align-items:center; justify-content:center; font-size:13px; }
  .mock-flag{ background:#2a2440; color:#d9d4f0; font-family:monospace; font-size:12px; text-align:center; padding:6px; }
  .finding{ border-bottom:1px solid #eef1f4; }
  .finding:last-child{ border-bottom:0; }
  .finding-head{ cursor:pointer; padding:12px 6px; margin:0; align-items:center; }
  .finding-head:hover{ background:#f5f9fd; }
  .finding-head h6{ margin:0; display:inline; font-weight:600; }
  .chev{ color:#0078D4; transition:transform .15s ease; margin-right:10px; width:12px; }
  .finding-head[aria-expanded="true"] .chev{ transform:rotate(90deg); }
  table.detail{ font-size:13px; margin-top:.6rem; margin-bottom:.25rem; }
  table.detail thead th{ background:#f1f5f9; border-bottom:2px solid #d7e0ea; font-size:12px; text-transform:uppercase; letter-spacing:.02em; color:#5a6b7b; padding:8px 10px; }
  table.detail td{ padding:8px 10px; vertical-align:top; }
  .rowstat{ white-space:nowrap; font-weight:600; }
  .remarks{ background:#f8f9fa; border:0; color:#495057; font-size:12.5px; }
  .remarks i{ color:#6c757d; margin-right:6px; }
  .learnmore{ margin-top:.6rem; padding-top:.5rem; border-top:1px dashed #e3e7eb; }
  .learnmore a{ text-decoration:none; display:block; padding:3px 0; }
  .lm-tag{ font-size:11px; color:#8a97a4; text-transform:uppercase; margin-left:6px; }
  .whyline{ color:#495057; margin:.15rem 0 .1rem; }
  /* executive summary */
  .es-meta{ color:#5a6b7b; font-size:13px; margin-bottom:.75rem; }
  .es-tiles{ display:flex; flex-wrap:wrap; gap:10px; margin-bottom:.85rem; }
  .es-tile{ border:1px solid #e3e9ef; border-radius:6px; padding:10px 14px; min-width:118px; text-align:center; }
  .es-num{ font-size:18px; font-weight:800; padding:6px 12px; display:inline-block; }
  .es-lbl{ font-size:11px; color:#5a6b7b; font-weight:600; text-transform:uppercase; letter-spacing:.02em; margin-top:6px; }
  .es-top{ font-weight:700; color:#33445a; margin-bottom:.35rem; }
  .es-list a.es-item{ display:flex; align-items:baseline; gap:7px; padding:3px 0; color:inherit; text-decoration:none; font-size:13.5px; }
  .es-list a.es-item:hover{ color:#0078D4; }
  .es-list .gdot{ align-self:center; }
  .es-sec{ color:#8a97a4; font-size:11.5px; margin-left:auto; padding-left:12px; white-space:nowrap; }
  .es-more{ color:#5a6b7b; font-size:12.5px; padding:4px 0 0 16px; font-style:italic; }
  .es-none{ color:#5a6b7b; font-size:13px; margin:0; }
  /* per-finding anchor affordance */
  .anchor-link{ margin-left:8px; color:#b7c6d6; text-decoration:none; font-weight:600; opacity:0; transition:opacity .12s ease; }
  .finding-head:hover .anchor-link{ opacity:1; }
  .anchor-link:hover{ color:#0078D4; text-decoration:none; }
  .anchor-link.copied{ color:#00bd19; opacity:1; }
  .finding:target{ background:#f0f7ff; }
  /* environment at a glance */
  .glance .cell{ display:block; border:1px solid #e3e9ef; border-radius:6px; padding:10px 12px; height:100%; text-decoration:none; color:inherit; transition:border-color .12s ease, background .12s ease; }
  .glance .cell:hover{ border-color:#0078D4; background:#f5f9fd; }
  .glance .nm{ font-size:12px; color:#5a6b7b; font-weight:600; display:flex; align-items:center; gap:7px; margin-bottom:3px; }
  .glance .mx{ font-size:20px; font-weight:800; letter-spacing:-.01em; line-height:1.1; }
  .glance .sub{ font-size:11px; color:#8a97a4; }
  .gdot{ width:9px; height:9px; border-radius:50%; display:inline-block; flex:none; }
  .gdot.ok{ background:#00bd19; } .gdot.impr{ background:#f0ad4e; } .gdot.rec{ background:#17a2b8; }
  .gdot.info{ background:#adb5bd; } .gdot.verify{ background:#6c757d; }
  /* solutions summary count badges */
  table.summary td{ vertical-align:middle; padding:6px 8px; }
  .sscount{ width:34px; padding:8px 0; text-align:center; display:inline-block; margin-left:2px; font-size:13px; }
  .ssparent{ background:#f1f5f9; }
  .ssparent td{ font-weight:700; color:#33445a; letter-spacing:.01em; }
  .sschild a{ color:#0078D4; text-decoration:none; }
  @media (prefers-reduced-motion:reduce){ .chev{ transition:none; } .glance .cell{ transition:none; } }
</style>
<title>Configuration Analyzer for Microsoft Purview</title>
</head>
<body class="app bg-light">
'@
}

function Get-PpaNavbarHtml {
@'
<nav class="navbar navbar-custom">
  <div class="container-fluid">
    <div class="col-sm" style="text-align:left"><div class="row"><div><i class="fas fa-binoculars"></i></div>
      <div class="ml-3"><strong>Configuration Analyzer for Microsoft Purview (CAMP)</strong></div></div></div>
    <div class="col-sm" style="text-align:right"><button type="button" class="btn btn-primary" onclick="window.print();">Print</button></div>
  </div>
</nav>
'@
}

function Get-PpaPolishScript {
    # Wave 3 interactive behaviors: vanilla JS, inline, no dependencies. Emitted once
    # before the footer. Everything here is progressive enhancement - the report stays
    # fully readable with scripting disabled.
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
})();
</script>
'@
}

function Get-PpaFooterHtml {
@'
<footer class="app-footer"><div class="container-fluid">
  <strong>CAMP v2 &middot; read-only.</strong> Reads configuration metadata only &mdash; no document, email or prompt content, no matched values.
  Does not create, modify or delete tenant configuration. Statuses are inputs to consultant judgment, not compliance determinations,
  and are not mapped to any regulatory framework.
</div></footer>

<script src="https://code.jquery.com/jquery-3.3.1.slim.min.js" integrity="sha384-q8i/X+965DzO0rT7abK41JStQIAqVgRVzpbzo5smXKp4YfRvH+8abtTE1Pi6jizo" crossorigin="anonymous"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.14.7/umd/popper.min.js" integrity="sha384-UO2eT0CpHqdSJQ6hJty5KVphtPhzWj9WO1clHTMGa3JDZwrnQq4sF86dIHNDz0W1" crossorigin="anonymous"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/js/bootstrap.min.js" integrity="sha384-JjSmVgyd0p3pXB1rRibZUAYoIIy6OrQ6VrjIEaFf/nJGzIxFDsf4x0xIM+B07jRM" crossorigin="anonymous"></script>
</body>
</html>
'@
}
