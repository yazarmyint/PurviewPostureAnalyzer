# Export-PpaDeltaReport.ps1 - renders the delta model as HTML (Wave 4 spec 4.5,
# reworked at C-fix 4/6). STRUCTURALLY shares the main report's render assets:
# Get-PpaHtmlHead embeds the SAME shared stylesheet (Get-PpaSharedReportCss - never
# hand-copied), the same navbar and footer chunks, and the same table.detail rules,
# so the delta report inherits fonts, bars, spacing and print behavior from one
# place. Every string flows through ConvertTo-PpaHtmlText / ConvertTo-PpaHtmlAttr;
# redaction (stable pseudonyms) applies at render iff -Redact/-RedactNames.
#
# Layout (C-fix 6): Comparison header card, then ONE "Assessment visibility" card
# collecting every VisibilityChanged / NotCompared / one-sided-check notice, then
# per-section cards carrying REAL changes only (headline tier, detail tier, always
# the unchanged count, finding status changes).
# ASCII-only source (parses under 5.1; executes under 7.5+).

Set-StrictMode -Off

function Get-PpaDeltaCss {
    # Delta-specific additions ONLY - everything else comes from the shared asset.
@'
  .chg-add{ color:#1e7e34; font-weight:700; } .chg-rem{ color:#c82333; font-weight:700; } .chg-mod{ color:#b8860b; font-weight:700; }
  .arrow{ color:#8a97a4; padding:0 4px; }
  .sig{ background:#fff3cd; border-radius:3px; padding:0 4px; font-size:11px; font-weight:700; color:#856404; margin-left:6px; text-transform:uppercase; }
  .tier{ font-size:12px; font-weight:700; color:#33445a; text-transform:uppercase; letter-spacing:.03em; margin:12px 0 2px; }
  .unch{ color:#5a6b7b; font-size:12.5px; margin:10px 0 2px; }
  .idwarn{ background:#fdecea; border:1px solid #d9534f; border-radius:5px; padding:8px 12px; margin:10px 0; font-size:13px; font-weight:600; }
  .vis-intro{ color:#495057; font-size:13px; margin:0 0 .5rem; }
  .vis-list{ margin:0; padding-left:0; list-style:none; }
  .vis-list li{ font-size:13px; padding:4px 0; border-bottom:1px dashed #e3e7eb; }
  .vis-list li:last-child{ border-bottom:0; }
  .delta-note{ color:#5a6b7b; font-size:12.5px; margin:1rem 2px 0; padding:8px 12px; background:#f1f5f9; border:1px solid #e3e9ef; border-radius:6px; }
'@
}

function Get-PpaDeltaSectionTitle {
    param([string]$Id)
    return ($Id -replace '_', ' ')
}

function Export-PpaDeltaReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Delta,
        [switch]$Redact,
        [switch]$RedactNames
    )

    if ($Redact -or $RedactNames) { Initialize-PpaDeltaRedaction -Delta $Delta -RedactNames:$RedactNames }
    else { Clear-PpaRedaction }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append((Get-PpaHtmlHead -Title 'Purview Posture Delta - Configuration Analyzer for Microsoft Purview' -ExtraCss (Get-PpaDeltaCss)))
    [void]$sb.Append((Get-PpaNavbarHtml))
    [void]$sb.AppendLine('<div class="container-fluid">')

    # ---- Comparison header card (spec 4.5) ----
    $span = [int]$Delta.spanDays
    [void]$sb.AppendLine('  <div class="card mt-3" id="delta-header"><div class="card-header"><strong>Snapshot Comparison</strong></div><div class="card-body">')
    [void]$sb.Append('    <p class="es-meta">From: snapshot <strong>').Append((ConvertTo-PpaHtmlText ([string]$Delta.from.snapshotId))).Append('</strong> captured ').Append((ConvertTo-PpaHtmlText ([string]$Delta.from.capturedAt))).AppendLine('</p>')
    [void]$sb.Append('    <p class="es-meta">To: snapshot <strong>').Append((ConvertTo-PpaHtmlText ([string]$Delta.to.snapshotId))).Append('</strong> captured ').Append((ConvertTo-PpaHtmlText ([string]$Delta.to.capturedAt))).AppendLine('</p>')
    $tenantDisp = [string]$Delta.from.tenantId
    if ([string]::IsNullOrEmpty($tenantDisp)) { $tenantDisp = '(not recorded)' }
    [void]$sb.Append('    <p class="es-meta">Tenant: ').Append((ConvertTo-PpaHtmlText $tenantDisp)).Append(' &middot; span: ').Append($span).AppendLine(' days</p>')
    if (-not [string]::IsNullOrEmpty([string]$Delta.denylistNote)) {
        [void]$sb.Append('    <div class="profile-note">').Append((ConvertTo-PpaHtmlText ([string]$Delta.denylistNote))).AppendLine('</div>')
    }
    if ($span -lt 0) {
        [void]$sb.AppendLine('    <div class="profile-note">The FROM snapshot is newer than the TO snapshot; the comparison reads right to left (inputs were not swapped).</div>')
    }
    [void]$sb.AppendLine('  </div></div>')

    # ---- Assessment visibility card (C-fix 6): every notice, stated ONCE ----
    $visItems = New-Object System.Collections.Generic.List[string]
    foreach ($sec in @($Delta.sections)) {
        $title = ConvertTo-PpaHtmlText (Get-PpaDeltaSectionTitle ([string]$sec.id))
        if ([string]$sec.state -eq 'NotCompared') {
            $visItems.Add('<li><strong>' + $title + '</strong> &mdash; not compared: ' + (ConvertTo-PpaHtmlText ([string]$sec.reason)) + '</li>')
        }
        elseif ([string]$sec.state -eq 'VisibilityChanged') {
            $noteTxt = [string]$sec.visibilityNote
            if ([string]::IsNullOrEmpty($noteTxt)) { $noteTxt = ('{0} -> {1}' -f [string]$sec.fromOutcome, [string]$sec.toOutcome) }
            $visItems.Add('<li><strong>' + $title + '</strong> &mdash; ' + (ConvertTo-PpaHtmlText $noteTxt) + '</li>')
        }
        foreach ($n in @($sec.findingNotices)) {
            $visItems.Add('<li><strong>' + $title + '</strong> &mdash; check ' + (ConvertTo-PpaHtmlText ([string]$n.checkId)) + ': ' + (ConvertTo-PpaHtmlText ([string]$n.reason)) + '</li>')
        }
    }
    if ($visItems.Count -gt 0) {
        [void]$sb.AppendLine('  <div class="card mt-3" id="delta-visibility"><div class="card-header"><strong>Assessment visibility</strong></div><div class="card-body">')
        [void]$sb.AppendLine('    <p class="vis-intro">The areas below could not be fully compared between the two snapshots. This reflects assessment visibility at capture time (permissions, module availability, or run scope) &mdash; it is not evidence of tenant change.</p>')
        [void]$sb.AppendLine('    <ul class="vis-list">')
        foreach ($li in $visItems) { [void]$sb.Append('      ').AppendLine($li) }
        [void]$sb.AppendLine('    </ul>')
        [void]$sb.AppendLine('  </div></div>')
    }

    # ---- per-section cards: REAL changes lead (C-fix 6) ----
    foreach ($sec in @($Delta.sections)) {
        $sid = [string]$sec.id
        $isCompared = ([string]$sec.state -eq 'Compared')
        $hasFindingChanges = (@($sec.findingChanges).Count -gt 0)
        if (-not $isCompared -and -not $hasFindingChanges) { continue }

        [void]$sb.Append('  <div class="card mt-3" id="delta-').Append((ConvertTo-PpaHtmlAttr $sid)).Append('"><div class="card-header"><strong>').Append((ConvertTo-PpaHtmlText (Get-PpaDeltaSectionTitle $sid))).AppendLine('</strong></div><div class="card-body">')

        if ($isCompared) {
            if ($sec.identityWarning) {
                [void]$sb.AppendLine('    <div class="idwarn">Warning: every object in this section appears Added AND Removed with nothing Modified or unchanged - this is the signature of an identity/keying failure, not a real wholesale replacement. Review the _keySource values in both snapshots before trusting this section.</div>')
            }

            $headlineRows = New-Object System.Collections.Generic.List[string]
            $detailRows   = New-Object System.Collections.Generic.List[string]
            foreach ($r in @($sec.added)) {
                $headlineRows.Add('<tr><td><span class="chg-add">Added</span></td><td>' + (ConvertTo-PpaHtmlText ([string]$r.type)) + '</td><td>' + (ConvertTo-PpaHtmlText ([string]$r.name)) + '</td><td>&#8212;</td></tr>')
            }
            foreach ($r in @($sec.removed)) {
                $headlineRows.Add('<tr><td><span class="chg-rem">Removed</span></td><td>' + (ConvertTo-PpaHtmlText ([string]$r.type)) + '</td><td>' + (ConvertTo-PpaHtmlText ([string]$r.name)) + '</td><td>&#8212;</td></tr>')
            }
            foreach ($m in @($sec.modified)) {
                $label = ConvertTo-PpaHtmlText ([string]$m.name)
                if ($m.renamed) {
                    $label = (ConvertTo-PpaHtmlText ([string]$m.renameFrom)) + '<span class="arrow">&rarr;</span>' + (ConvertTo-PpaHtmlText ([string]$m.renameTo)) + ' <span class="sig">renamed</span>'
                }
                foreach ($c in @($m.changes)) {
                    $row = '<tr><td><span class="chg-mod">Modified</span></td><td>' + (ConvertTo-PpaHtmlText ([string]$m.type)) + '</td><td>' + $label + '</td><td>' +
                        (ConvertTo-PpaHtmlText ([string]$c.property)) + ': ' + (ConvertTo-PpaHtmlText ([string]$c.from)) + '<span class="arrow">&rarr;</span>' + (ConvertTo-PpaHtmlText ([string]$c.to))
                    if ($c.significant) { $row += ' <span class="sig">significant</span>' }
                    $row += '</td></tr>'
                    if ($c.significant -or $m.renamed) { $headlineRows.Add($row) } else { $detailRows.Add($row) }
                }
                if (@($m.changes).Count -eq 0 -and $m.renamed) {
                    $headlineRows.Add('<tr><td><span class="chg-mod">Modified</span></td><td>' + (ConvertTo-PpaHtmlText ([string]$m.type)) + '</td><td>' + $label + '</td><td>&#8212;</td></tr>')
                }
            }
            if ($headlineRows.Count -gt 0) {
                [void]$sb.AppendLine('    <div class="tier">Headline changes</div>')
                [void]$sb.AppendLine('    <table class="table table-sm detail"><thead><tr><th>Change</th><th>Type</th><th>Object</th><th>Detail</th></tr></thead><tbody>')
                foreach ($r in $headlineRows) { [void]$sb.Append('      ').AppendLine($r) }
                [void]$sb.AppendLine('    </tbody></table>')
            }
            if ($detailRows.Count -gt 0) {
                [void]$sb.AppendLine('    <div class="tier">Detail changes</div>')
                [void]$sb.AppendLine('    <table class="table table-sm detail"><thead><tr><th>Change</th><th>Type</th><th>Object</th><th>Detail</th></tr></thead><tbody>')
                foreach ($r in $detailRows) { [void]$sb.Append('      ').AppendLine($r) }
                [void]$sb.AppendLine('    </tbody></table>')
            }
            if ($headlineRows.Count -eq 0 -and $detailRows.Count -eq 0) {
                [void]$sb.AppendLine('    <p class="es-meta">No object-level changes.</p>')
            }
            # ALWAYS the unchanged count - the confidence signal (spec 4.5).
            [void]$sb.Append('    <p class="unch">').Append([int]$sec.unchangedCount).AppendLine(' unchanged object(s) in this section.</p>')
        }

        if ($hasFindingChanges) {
            [void]$sb.AppendLine('    <div class="tier">Finding changes</div>')
            [void]$sb.AppendLine('    <table class="table table-sm detail"><thead><tr><th>Check</th><th>Title</th><th>Status</th></tr></thead><tbody>')
            foreach ($f in @($sec.findingChanges)) {
                [void]$sb.Append('      <tr><td>').Append((ConvertTo-PpaHtmlText ([string]$f.checkId))).Append('</td><td>').Append((ConvertTo-PpaHtmlText ([string]$f.title))).Append('</td><td>')
                [void]$sb.Append((ConvertTo-PpaHtmlText ([string]$f.fromStatus))).Append('<span class="arrow">&rarr;</span>').Append((ConvertTo-PpaHtmlText ([string]$f.toStatus))).AppendLine('</td></tr>')
            }
            [void]$sb.AppendLine('    </tbody></table>')
        }

        [void]$sb.AppendLine('  </div></div>')
    }

    [void]$sb.AppendLine('  <div class="delta-note">Offline comparison of two read-only snapshots. Object changes reflect configuration metadata only; unchanged counts state how much of each section was verified identical. Statuses are inputs to user judgment, not compliance determinations.</div>')
    [void]$sb.AppendLine('</div>')
    [void]$sb.Append((Get-PpaFooterHtml))

    $html = $sb.ToString()
    Clear-PpaRedaction
    return $html
}
