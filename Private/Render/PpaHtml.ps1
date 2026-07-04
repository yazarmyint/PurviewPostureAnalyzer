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
    [void]$sb.AppendLine('            <summary><i class="fas fa-tools"></i> How to remediate <span class="remed-draft-tag">draft</span></summary>')
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
    [void]$sb.AppendLine('              <p class="remed-note">Draft guidance shown for planning - verify against current Microsoft Learn before acting. This tool never executes remediation.</p>')
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
# Static document chunks (verbatim from posture-report-mock-v5.html; CDN assets)
# ---------------------------------------------------------------------------

function Get-PpaSharedReportCss {
    # The single shared stylesheet (C-fix 4): consumed by BOTH the main report head
    # and the delta report head, so the two artifacts render as one product family.
    # Never hand-copy these rules into another template.
    #
    # Wave 5 port (framework-free / offline): three layers, in order -
    #   1. compat - re-implements the Bootstrap 4 subset the markup uses (grid, card,
    #      badge, table, btn) + a Font Awesome -> monochrome-unicode map, so the report
    #      renders with NO CDN. (The CDN <link>/<script> tags are gone from the head/footer.)
    #   2. polished - CSS custom properties (:root tokens) + the tokenized component CSS
    #      (contrast/gray/border/surface consolidation, unified severity colors, focus
    #      states, type/spacing/radius scale). The @media print block + covm gradient
    #      patterns are preserved verbatim (Pester asserts those substrings).
    #   3. collapse addendum - the .sumhead / .sum-glance rules for the collapsible
    #      Posture Summary + Coverage Matrix headers.
@'
  /* ---- 1. framework-free compat layer (replaces Bootstrap + Font Awesome CDN) ---- */
  *,*::before,*::after{box-sizing:border-box;}
  body{margin:0;font-family:var(--font-sans);line-height:1.45;color:var(--text-body);}
  img{max-width:100%;height:auto;}
  h2{font-size:2rem;font-weight:500;margin:0 0 .5rem;line-height:1.2;}
  h5{font-size:1.25rem;font-weight:500;margin:0 0 .5rem;}
  h6{font-size:1rem;font-weight:500;margin:0 0 .5rem;}
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
  .ml-3{margin-left:1rem;} .mt-3{margin-top:1rem;} .p-3{padding:1rem;}
  .text-success{color:var(--sev-ok);} .text-danger{color:#c0392b;}
  .text-muted{color:var(--text-faint);} .text-secondary{color:var(--sev-verify);}
  .bg-light{background:#f8f9fa;}
  .card{position:relative;background:var(--surface);border:1px solid var(--hairline);border-radius:var(--radius-md);}
  .card-body{padding:1rem 1.25rem;}
  .card-title{margin-bottom:.75rem;}
  table{border-collapse:collapse;}
  .table{width:100%;margin-bottom:1rem;}
  .table td,.table th{padding:.45rem .5rem;text-align:left;}
  .table-sm td,.table-sm th{padding:.3rem .4rem;}
  .table-borderless td,.table-borderless th{border:0;}
  .badge{display:inline-block;padding:.25em .4em;font-size:75%;font-weight:700;line-height:1;text-align:center;white-space:nowrap;border-radius:var(--radius-sm);vertical-align:baseline;}
  .badge-success{background:var(--badge-ok-bg);color:var(--badge-ok-fg);}
  .badge-warning{background:var(--badge-impr-bg);color:var(--badge-impr-fg);}
  .badge-info{background:var(--badge-rec-bg);color:var(--badge-rec-fg);}
  .badge-secondary{background:var(--badge-info-bg);color:var(--badge-info-fg);}
  .badge-dark{background:var(--badge-verify-bg);color:var(--badge-verify-fg);}
  .btn{display:inline-block;font-weight:400;text-align:center;padding:.375rem .75rem;font-size:1rem;line-height:1.5;border:1px solid transparent;border-radius:.25rem;cursor:pointer;}
  .btn-primary{color:#fff;background:#007bff;border-color:#007bff;}
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
  /* ---- 2. tokens + tokenized/polished component CSS ---- */
  :root{
    --font-sans:'Segoe UI',system-ui,-apple-system,BlinkMacSystemFont,Roboto,Helvetica,Arial,sans-serif;
    --fs-xs:11px; --fs-sm:12px; --fs-base:13px; --fs-md:14px; --fs-lg:18px; --fs-xl:20px;
    --sp-1:4px; --sp-2:6px; --sp-3:8px; --sp-4:10px; --sp-5:12px; --sp-6:16px;
    --radius-sm:4px; --radius-md:6px; --radius-pill:14px;
    --brand:#005494; --brand-header:#0078D4; --accent:#0078D4; --accent-strong:#0b5394;
    --accent-soft:#eaf4fd; --target:#f0f7ff;
    --text-strong:#33445a; --text-body:#495057; --text-muted:#5a6b7b; --text-faint:#667085;
    --surface:#ffffff; --surface-1:#f8fafc; --surface-2:#f1f5f9; --hover:#f5f9fd;
    --hairline:#e6ebf1; --border:#d7e0ea;
    --sev-ok:#1e7e34; --sev-impr:#f0ad4e; --sev-rec:#17a2b8; --sev-info:#adb5bd; --sev-verify:#6c757d;
    --badge-ok-bg:#1e7e34; --badge-ok-fg:#ffffff;
    --badge-impr-bg:#ffc107; --badge-impr-fg:#212529;
    --badge-rec-bg:#17a2b8; --badge-rec-fg:#ffffff;
    --badge-info-bg:#6c757d; --badge-info-fg:#ffffff;
    --badge-verify-bg:#343a40; --badge-verify-fg:#ffffff;
  }
  a:focus-visible,button:focus-visible,input:focus-visible,summary:focus-visible,[tabindex]:focus-visible{
    outline:2px solid var(--accent); outline-offset:2px; border-radius:2px; }
  .navbar-custom{ background-color:var(--brand); color:#fff; padding-bottom:10px; }
  .card-header{ background-color:var(--brand-header); color:#fff; padding:.6rem 1.25rem; border-radius:var(--radius-md) var(--radius-md) 0 0; }
  .card-header a{ color:#fff; text-decoration:none; }
  .bd-callout{ padding:1rem 1.25rem; margin:.5rem 0 1rem; border:1px solid var(--hairline); border-left-width:.25rem; border-radius:var(--radius-sm); background:var(--surface); }
  .bd-callout-info{ border-left-color:var(--sev-rec); }
  .bd-callout-warning{ border-left-color:var(--sev-impr); }
  .bd-callout-success{ border-left-color:var(--sev-ok); }
  .bd-callout-secondary{ border-left-color:var(--sev-info); }
  .bd-callout-dark{ border-left-color:var(--sev-verify); }
  .app-footer{ background-color:var(--brand); color:#fff; padding:12px 0; }
  .app-footer a{ color:#cfe6ff; }
  .logo-ph{ width:250px; height:150px; border:1px dashed var(--border); border-radius:var(--radius-sm); color:var(--text-faint); display:flex; align-items:center; justify-content:center; font-size:var(--fs-base); }
  .mock-flag{ background:#2a2440; color:#d9d4f0; font-family:monospace; font-size:var(--fs-sm); text-align:center; padding:var(--sp-2); }
  .redact-flag{ background:#5c1a1a; color:#ffd9d9; font-family:monospace; font-size:var(--fs-sm); text-align:center; padding:var(--sp-2); }
  .finding{ border-bottom:1px solid var(--hairline); }
  .finding:last-child{ border-bottom:0; }
  .finding-head{ cursor:pointer; padding:var(--sp-5) var(--sp-3); margin:0; align-items:center; }
  .finding-head:hover{ background:var(--hover); }
  .finding-head h6{ margin:0; display:inline; font-weight:600; }
  .chev{ color:var(--accent); transition:transform .15s ease; margin-right:10px; width:12px; }
  .finding-head[aria-expanded="true"] .chev{ transform:rotate(90deg); }
  table.detail{ font-size:var(--fs-base); margin-top:.6rem; margin-bottom:.25rem; }
  table.detail thead th{ background:var(--surface-2); border-bottom:2px solid var(--border); font-size:var(--fs-sm); text-transform:uppercase; letter-spacing:.02em; color:var(--text-muted); padding:var(--sp-3) var(--sp-4); }
  table.detail td{ padding:var(--sp-3) var(--sp-4); vertical-align:top; }
  .rowstat{ white-space:nowrap; font-weight:600; }
  .remarks{ background:var(--surface-1); border:0; color:var(--text-body); font-size:var(--fs-sm); }
  .remarks i{ color:var(--text-faint); margin-right:6px; }
  .learnmore{ margin-top:.6rem; padding-top:.5rem; border-top:1px dashed var(--hairline); }
  .learnmore a{ text-decoration:none; display:block; padding:3px 0; }
  .lm-tag{ font-size:var(--fs-xs); color:var(--text-faint); text-transform:uppercase; margin-left:6px; }
  .whyline{ color:var(--text-body); margin:.15rem 0 .1rem; }
  /* filter bar */
  .filterbar{ position:sticky; top:8px; z-index:100; background:var(--surface); border:1px solid var(--hairline); border-radius:var(--radius-md);
              padding:var(--sp-3) var(--sp-5); margin-top:1rem; display:flex; flex-wrap:wrap; align-items:center; gap:var(--sp-3);
              box-shadow:0 2px 8px rgba(0,40,80,.08); }
  .fb-label{ font-size:var(--fs-sm); font-weight:700; color:var(--text-strong); text-transform:uppercase; letter-spacing:.02em; }
  .fb-chip{ border:1px solid var(--border); background:var(--surface-1); border-radius:var(--radius-pill); font-size:var(--fs-sm); font-weight:600;
            color:var(--text-muted); padding:3px 11px; cursor:pointer; display:inline-flex; align-items:center; gap:6px; }
  .fb-chip:hover{ border-color:var(--accent); }
  .fb-chip.active{ background:var(--accent-soft); border-color:var(--accent); color:var(--accent-strong); }
  .fb-chip:not(.active) .gdot{ opacity:.35; }
  .fb-search{ border:1px solid var(--border); border-radius:var(--radius-sm); font-size:var(--fs-base); padding:4px 10px; min-width:220px; flex:1 1 220px; max-width:340px; }
  .fb-search:focus{ border-color:var(--accent); }
  .fb-reset{ border:1px solid var(--border); background:var(--surface); border-radius:var(--radius-sm); font-size:var(--fs-sm); font-weight:600; color:var(--text-muted); padding:4px 12px; cursor:pointer; }
  .fb-reset:hover{ border-color:var(--accent); color:var(--accent-strong); }
  .fb-status{ font-size:var(--fs-sm); color:var(--text-faint); margin-left:auto; }
  .finding.fb-hidden{ display:none; }
  .seccard.sec-allhidden .card-body{ display:none; }
  .sec-hiddennote{ display:none; font-size:var(--fs-sm); font-weight:400; color:#cfe6ff; margin-left:10px; }
  .seccard.sec-allhidden .sec-hiddennote{ display:inline; }
  /* posture summary */
  .es-meta{ color:var(--text-muted); font-size:var(--fs-base); margin-bottom:.75rem; }
  .es-tiles{ display:flex; flex-wrap:wrap; gap:var(--sp-4); margin-bottom:.85rem; }
  .es-tile{ border:1px solid var(--hairline); border-radius:var(--radius-md); padding:var(--sp-4) var(--sp-6); min-width:118px; text-align:center; }
  .es-num{ font-size:var(--fs-lg); font-weight:800; padding:6px 12px; display:inline-block; }
  .es-lbl{ font-size:var(--fs-xs); color:var(--text-muted); font-weight:600; text-transform:uppercase; letter-spacing:.02em; margin-top:6px; }
  .es-top{ font-weight:700; color:var(--text-strong); margin-bottom:.35rem; }
  .es-list a.es-item{ display:flex; align-items:baseline; gap:7px; padding:3px 0; color:inherit; text-decoration:none; font-size:var(--fs-base); }
  .es-list a.es-item:hover{ color:var(--accent); }
  .es-list .gdot{ align-self:center; }
  .es-sec{ color:var(--text-faint); font-size:var(--fs-sm); margin-left:auto; padding-left:12px; white-space:nowrap; }
  .es-more{ color:var(--text-muted); font-size:var(--fs-sm); padding:4px 0 0 16px; font-style:italic; }
  .es-none{ color:var(--text-muted); font-size:var(--fs-base); margin:0; }
  /* remediation region (P7) */
  details.remed{ margin-top:.6rem; border-top:1px dashed var(--hairline); padding-top:.5rem; }
  details.remed summary{ cursor:pointer; font-size:var(--fs-base); font-weight:600; color:var(--accent-strong); list-style-position:inside; }
  details.remed summary i{ margin-right:4px; color:var(--accent); }
  .remed-draft-tag{ font-size:var(--fs-xs); color:var(--text-faint); text-transform:uppercase; letter-spacing:.04em; border:1px solid var(--border); border-radius:var(--radius-sm); padding:1px 5px; margin-left:6px; vertical-align:middle; }
  .remed-body{ padding:var(--sp-3) var(--sp-1) var(--sp-1); }
  .remed-portal{ font-size:var(--fs-base); margin-bottom:.5rem; }
  .remed-learn{ font-size:var(--fs-base); text-decoration:none; display:inline-block; padding:2px 0; }
  .remed-note{ font-size:var(--fs-sm); color:var(--text-faint); margin:.4rem 0 0; }
  /* run-profile exclusion note */
  .profile-note{ color:var(--text-muted); font-size:var(--fs-sm); margin:1rem 2px 0; padding:var(--sp-3) var(--sp-5); background:var(--surface-2); border:1px solid var(--hairline); border-radius:var(--radius-md); }
  /* per-finding anchor affordance */
  .anchor-link{ margin-left:8px; color:var(--text-faint); text-decoration:none; font-weight:600; opacity:0; transition:opacity .12s ease; }
  .finding-head:hover .anchor-link{ opacity:1; }
  .anchor-link:hover{ color:var(--accent); text-decoration:none; }
  .anchor-link.copied{ color:var(--sev-ok); opacity:1; }
  .finding:target{ background:var(--target); }
  /* environment at a glance */
  .glance .cell{ display:block; border:1px solid var(--hairline); border-radius:var(--radius-md); padding:var(--sp-4) var(--sp-5); height:100%; text-decoration:none; color:inherit; transition:border-color .12s ease, background .12s ease; }
  .glance .cell:hover{ border-color:var(--accent); background:var(--hover); }
  .glance .nm{ font-size:var(--fs-sm); color:var(--text-muted); font-weight:600; display:flex; align-items:center; gap:7px; margin-bottom:3px; }
  .glance .mx{ font-size:var(--fs-xl); font-weight:800; letter-spacing:-.01em; line-height:1.1; }
  .glance .sub{ font-size:var(--fs-xs); color:var(--text-faint); }
  .gdot{ width:9px; height:9px; border-radius:50%; display:inline-block; flex:none; }
  .gdot.ok{ background:var(--sev-ok); } .gdot.impr{ background:var(--sev-impr); } .gdot.rec{ background:var(--sev-rec); }
  .gdot.info{ background:var(--sev-info); } .gdot.verify{ background:var(--sev-verify); }
  /* solutions summary count badges */
  table.summary td{ vertical-align:middle; padding:var(--sp-2) var(--sp-3); }
  .sscount{ width:34px; padding:var(--sp-3) 0; text-align:center; display:inline-block; margin-left:2px; font-size:var(--fs-base); }
  .ssparent{ background:var(--surface-2); }
  .ssparent td{ font-weight:700; color:var(--text-strong); letter-spacing:.01em; }
  .sschild a{ color:var(--accent); text-decoration:none; }
  /* coverage matrix (Wave 4 Part D). None vs Unknown must survive print WITHOUT
     color: distinct family + hatching (repeating stripes) vs dotting (radial) +
     glyph + in-cell text - four independent signals. */
  table.covm-grid{ border-collapse:collapse; width:100%; font-size:var(--fs-base); margin-top:.4rem; }
  table.covm-grid thead th{ background:var(--surface-2); border:1px solid var(--border); font-size:var(--fs-sm); text-transform:uppercase; letter-spacing:.02em; color:var(--text-muted); padding:var(--sp-3) var(--sp-4); text-align:center; }
  table.covm-grid th.covm-row{ background:var(--surface-1); border:1px solid var(--border); text-align:left; padding:var(--sp-3) var(--sp-4); font-size:var(--fs-sm); color:var(--text-strong); width:16%; }
  td.covm-cell{ border:1px solid var(--border); padding:var(--sp-3) var(--sp-4); text-align:center; vertical-align:middle; }
  .covm-cell a.covm-link{ text-decoration:none; color:inherit; }
  .covm-glyph{ font-weight:800; margin-right:5px; }
  .covm-text{ font-weight:600; font-size:var(--fs-sm); }
  .covm-covered{ background:#e6f6e9; color:#1e7e34; }
  .covm-partial{ background:#fff6e0; color:#8a6d1a; }
  .covm-testonly{ background:#eef4fa; color:var(--accent-strong); }
  .covm-none{ background:repeating-linear-gradient(45deg,#fdecea,#fdecea 6px,#ffffff 6px,#ffffff 12px); color:#a52834; }
  .covm-unknown{ background:radial-gradient(#cfd6dd 1.3px, #f8f9fa 1.3px); background-size:8px 8px; color:var(--text-body); }
  .covm-na{ background:var(--surface-1); color:var(--text-faint); }
  .covm-held{ background:#ffffff; color:var(--text-faint); }
  .covm-held sup a{ text-decoration:none; }
  .covm-reason{ display:inline-block; border:1px solid var(--border); border-radius:var(--radius-md); font-size:10px; padding:0 6px; margin-top:3px; color:var(--text-muted); background:var(--surface); }
  .covm-prov{ color:#b07d2b; margin-left:4px; cursor:help; font-weight:700; }
  .covm-banner{ background:#fff8e6; border:1px solid var(--sev-impr); border-radius:var(--radius-md); padding:var(--sp-3) var(--sp-5); margin-bottom:.6rem; font-size:var(--fs-base); }
  .covm-strip{ font-size:var(--fs-base); margin:.7rem 0 0; color:var(--text-strong); }
  .covm-strip a{ color:var(--accent); text-decoration:none; }
  .covm-foot{ color:var(--text-faint); font-size:var(--fs-sm); margin:.5rem 0 0; }
  @media (prefers-reduced-motion:reduce){ .chev{ transition:none; } .glance .cell{ transition:none; } }
  /* ---- 3. collapsible Posture Summary + Coverage Matrix headers ---- */
  .card-header.sumhead{ display:flex; align-items:center; cursor:pointer; }
  .card-header.sumhead:hover{ background:#0a6bc0; }
  .sumhead .chev{ color:#fff; margin-right:8px; width:12px; }
  .sumhead[aria-expanded="true"] .chev{ transform:rotate(90deg); }
  .sum-glance{ margin-left:auto; display:inline-flex; align-items:center; flex-wrap:wrap; gap:12px; font-size:var(--fs-base); font-weight:600; color:#fff; }
  .sum-glance .sg-item{ display:inline-flex; align-items:center; gap:5px; }
  .sum-glance .gdot{ box-shadow:0 0 0 1.5px rgba(255,255,255,.55); }
  /* print / PDF (P3): posture summary is page one, sections start clean, drill-downs
     expanded (beforeprint JS opens them; the .collapse rule is the CSS fallback),
     interactive-only affordances hidden, severity colors preserved. */
  @media print{
    *{ print-color-adjust:exact; -webkit-print-color-adjust:exact; }
    body{ background:#fff; }
    .filterbar, .anchor-link, .backlink, .navbar-custom .btn, .mock-flag, .chev{ display:none !important; }
    .collapse{ display:block !important; height:auto !important; }
    .postsum{ break-after:page; page-break-after:always; }
    .seccard{ break-before:page; page-break-before:always; }
    .finding, .glance .cell, .bd-callout{ break-inside:avoid; page-break-inside:avoid; }
    .finding-head{ cursor:default; }
    .card-header.sumhead{ cursor:default; }
    .card{ border:1px solid #d7e0ea; }
  }
'@
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
    return Get-PpaHtmlHead -Title 'Configuration Analyzer for Microsoft Purview'
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
</script>
'@
}

function Get-PpaFooterHtml {
    # Wave 5: framework-free / offline - the CDN jQuery/Popper/Bootstrap <script> tags are
    # gone; all interactivity is the vanilla JS in Get-PpaPolishScript (incl. collapse).
@'
<footer class="app-footer"><div class="container-fluid">
  <strong>CAMP v2 &middot; read-only.</strong> Reads configuration metadata only &mdash; no document, email or prompt content, no matched values.
  Does not create, modify or delete tenant configuration. Statuses are inputs to consultant judgment, not compliance determinations,
  and are not mapped to any regulatory framework.
</div></footer>
</body>
</html>
'@
}
