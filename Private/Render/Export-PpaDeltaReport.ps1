# Export-PpaDeltaReport.ps1 - renders the delta model as a standalone HTML page
# (Wave 4 spec 4.5). Reuses the existing render boundary: every string flows through
# ConvertTo-PpaHtmlText / ConvertTo-PpaHtmlAttr (unconditional HTML encoding), and
# redaction (stable pseudonyms) is applied at render iff -Redact/-RedactNames.
# Snapshots themselves stay unredacted - redaction is a render-time concern (ruled).
# Two tiers per section: HEADLINE (added/removed/renames/significant changes) and
# DETAIL (other modified properties), plus VisibilityChanged / NotCompared notices
# and ALWAYS the per-section unchanged count. Print stylesheet and per-section
# anchors follow the Wave 3 report patterns. Self-contained: no CDN assets.
# ASCII-only source (parses under 5.1; executes under 7+).

Set-StrictMode -Off

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
    [void]$sb.AppendLine('<!doctype html>')
    [void]$sb.AppendLine('<html lang="en"><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine('<title>Purview Posture Delta</title>')
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine('  body{ font-family:"Segoe UI",Arial,sans-serif; background:#f4f6f8; color:#212529; margin:0; }')
    [void]$sb.AppendLine('  .topbar{ background:#005494; color:#fff; padding:14px 22px; font-size:17px; font-weight:700; }')
    [void]$sb.AppendLine('  .wrap{ max-width:1080px; margin:0 auto; padding:16px 22px 40px; }')
    [void]$sb.AppendLine('  .card{ background:#fff; border:1px solid #d7e0ea; border-radius:6px; margin-top:16px; overflow:hidden; }')
    [void]$sb.AppendLine('  .card-h{ background:#0078D4; color:#fff; padding:9px 14px; font-weight:700; }')
    [void]$sb.AppendLine('  .card-b{ padding:12px 16px; }')
    [void]$sb.AppendLine('  .meta{ color:#5a6b7b; font-size:13px; margin:4px 0; }')
    [void]$sb.AppendLine('  .warn{ background:#fff8e6; border:1px solid #f0ad4e; border-radius:5px; padding:8px 12px; margin:10px 0; font-size:13px; }')
    [void]$sb.AppendLine('  .idwarn{ background:#fdecea; border:1px solid #d9534f; border-radius:5px; padding:8px 12px; margin:10px 0; font-size:13px; font-weight:600; }')
    [void]$sb.AppendLine('  .note{ background:#eef4fa; border:1px solid #b8d4ee; border-radius:5px; padding:8px 12px; margin:10px 0; font-size:13px; }')
    [void]$sb.AppendLine('  .chg-add{ color:#1e7e34; font-weight:700; } .chg-rem{ color:#c82333; font-weight:700; } .chg-mod{ color:#b8860b; font-weight:700; }')
    [void]$sb.AppendLine('  table.delta{ border-collapse:collapse; width:100%; font-size:13px; margin:8px 0; }')
    [void]$sb.AppendLine('  table.delta th{ background:#f1f5f9; border-bottom:2px solid #d7e0ea; text-align:left; padding:6px 9px; font-size:12px; text-transform:uppercase; color:#5a6b7b; }')
    [void]$sb.AppendLine('  table.delta td{ border-bottom:1px solid #eef1f4; padding:6px 9px; vertical-align:top; }')
    [void]$sb.AppendLine('  .tier{ font-size:12px; font-weight:700; color:#33445a; text-transform:uppercase; letter-spacing:.03em; margin:12px 0 2px; }')
    [void]$sb.AppendLine('  .unch{ color:#5a6b7b; font-size:12.5px; margin:10px 0 2px; }')
    [void]$sb.AppendLine('  .arrow{ color:#8a97a4; padding:0 4px; }')
    [void]$sb.AppendLine('  .sig{ background:#fff3cd; border-radius:3px; padding:0 4px; font-size:11px; font-weight:700; color:#856404; margin-left:6px; text-transform:uppercase; }')
    [void]$sb.AppendLine('  .foot{ color:#5a6b7b; font-size:12px; margin-top:26px; border-top:1px solid #d7e0ea; padding-top:10px; }')
    [void]$sb.AppendLine('  @media print{ *{ print-color-adjust:exact; -webkit-print-color-adjust:exact; } body{ background:#fff; } .card{ break-inside:avoid; page-break-inside:avoid; border:1px solid #d7e0ea; } }')
    [void]$sb.AppendLine('</style></head><body>')
    [void]$sb.AppendLine('<div class="topbar">Configuration Analyzer for Microsoft Purview (CAMP) &mdash; Snapshot Delta</div>')
    [void]$sb.AppendLine('<div class="wrap">')

    # ---- header: both snapshot identities, tenant, span (spec 4.5) ----
    $span = [int]$Delta.spanDays
    [void]$sb.AppendLine('  <div class="card" id="delta-header"><div class="card-h">Comparison</div><div class="card-b">')
    [void]$sb.Append('    <p class="meta">From: snapshot <strong>').Append((ConvertTo-PpaHtmlText ([string]$Delta.from.snapshotId))).Append('</strong> captured ').Append((ConvertTo-PpaHtmlText ([string]$Delta.from.capturedAt))).AppendLine('</p>')
    [void]$sb.Append('    <p class="meta">To: snapshot <strong>').Append((ConvertTo-PpaHtmlText ([string]$Delta.to.snapshotId))).Append('</strong> captured ').Append((ConvertTo-PpaHtmlText ([string]$Delta.to.capturedAt))).AppendLine('</p>')
    $tenantDisp = [string]$Delta.from.tenantId
    if ([string]::IsNullOrEmpty($tenantDisp)) { $tenantDisp = '(not recorded)' }
    [void]$sb.Append('    <p class="meta">Tenant: ').Append((ConvertTo-PpaHtmlText $tenantDisp)).Append(' &middot; span: ').Append($span).AppendLine(' days</p>')
    if (-not [string]::IsNullOrEmpty([string]$Delta.denylistNote)) {
        [void]$sb.Append('    <div class="note">').Append((ConvertTo-PpaHtmlText ([string]$Delta.denylistNote))).AppendLine('</div>')
    }
    if ($span -lt 0) {
        [void]$sb.AppendLine('    <div class="warn">The FROM snapshot is newer than the TO snapshot; the comparison reads right to left (inputs were not swapped).</div>')
    }
    [void]$sb.AppendLine('  </div></div>')

    # ---- per-section blocks ----
    foreach ($sec in @($Delta.sections)) {
        $sid = [string]$sec.id
        [void]$sb.Append('  <div class="card" id="delta-').Append((ConvertTo-PpaHtmlAttr $sid)).Append('"><div class="card-h">').Append((ConvertTo-PpaHtmlText ($sid -replace '_', ' '))).AppendLine('</div><div class="card-b">')

        if ([string]$sec.state -eq 'NotCompared') {
            [void]$sb.Append('    <div class="note">Not compared: ').Append((ConvertTo-PpaHtmlText ([string]$sec.reason))).AppendLine('</div>')
        }
        elseif ([string]$sec.state -eq 'VisibilityChanged') {
            $noteTxt = [string]$sec.visibilityNote
            if ([string]::IsNullOrEmpty($noteTxt)) { $noteTxt = ('{0} -> {1}' -f [string]$sec.fromOutcome, [string]$sec.toOutcome) }
            [void]$sb.Append('    <div class="warn">Visibility changed (').Append((ConvertTo-PpaHtmlText ([string]$sec.fromOutcome))).Append(' &rarr; ').Append((ConvertTo-PpaHtmlText ([string]$sec.toOutcome))).Append('): ')
            [void]$sb.Append((ConvertTo-PpaHtmlText $noteTxt)).AppendLine('</div>')
        }
        else {
            if ($sec.identityWarning) {
                [void]$sb.AppendLine('    <div class="idwarn">Warning: every object in this section appears Added AND Removed with nothing Modified or unchanged - this is the signature of an identity/keying failure, not a real wholesale replacement. Review the _keySource values in both snapshots before trusting this section.</div>')
            }

            # HEADLINE tier: adds, removes, renames, significant property changes.
            $headlineRows = New-Object System.Collections.Generic.List[string]
            foreach ($r in @($sec.added)) {
                $headlineRows.Add('<tr><td><span class="chg-add">Added</span></td><td>' + (ConvertTo-PpaHtmlText ([string]$r.type)) + '</td><td>' + (ConvertTo-PpaHtmlText ([string]$r.name)) + '</td><td>&mdash;</td></tr>')
            }
            foreach ($r in @($sec.removed)) {
                $headlineRows.Add('<tr><td><span class="chg-rem">Removed</span></td><td>' + (ConvertTo-PpaHtmlText ([string]$r.type)) + '</td><td>' + (ConvertTo-PpaHtmlText ([string]$r.name)) + '</td><td>&mdash;</td></tr>')
            }
            $detailRows = New-Object System.Collections.Generic.List[string]
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
                    $headlineRows.Add('<tr><td><span class="chg-mod">Modified</span></td><td>' + (ConvertTo-PpaHtmlText ([string]$m.type)) + '</td><td>' + $label + '</td><td>&mdash;</td></tr>')
                }
            }
            if ($headlineRows.Count -gt 0) {
                [void]$sb.AppendLine('    <div class="tier">Headline changes</div>')
                [void]$sb.AppendLine('    <table class="delta"><thead><tr><th>Change</th><th>Type</th><th>Object</th><th>Detail</th></tr></thead><tbody>')
                foreach ($r in $headlineRows) { [void]$sb.Append('      ').AppendLine($r) }
                [void]$sb.AppendLine('    </tbody></table>')
            }
            if ($detailRows.Count -gt 0) {
                [void]$sb.AppendLine('    <div class="tier">Detail changes</div>')
                [void]$sb.AppendLine('    <table class="delta"><thead><tr><th>Change</th><th>Type</th><th>Object</th><th>Detail</th></tr></thead><tbody>')
                foreach ($r in $detailRows) { [void]$sb.Append('      ').AppendLine($r) }
                [void]$sb.AppendLine('    </tbody></table>')
            }
            if ($headlineRows.Count -eq 0 -and $detailRows.Count -eq 0) {
                [void]$sb.AppendLine('    <p class="meta">No object-level changes.</p>')
            }
            # ALWAYS the unchanged count - the confidence signal (spec 4.5).
            [void]$sb.Append('    <p class="unch">').Append([int]$sec.unchangedCount).AppendLine(' unchanged object(s) in this section.</p>')
        }

        # Finding status changes render for every section compared on both sides.
        if (@($sec.findingChanges).Count -gt 0) {
            [void]$sb.AppendLine('    <div class="tier">Finding changes</div>')
            [void]$sb.AppendLine('    <table class="delta"><thead><tr><th>Check</th><th>Title</th><th>Status</th></tr></thead><tbody>')
            foreach ($f in @($sec.findingChanges)) {
                [void]$sb.Append('      <tr><td>').Append((ConvertTo-PpaHtmlText ([string]$f.checkId))).Append('</td><td>').Append((ConvertTo-PpaHtmlText ([string]$f.title))).Append('</td><td>')
                [void]$sb.Append((ConvertTo-PpaHtmlText ([string]$f.fromStatus))).Append('<span class="arrow">&rarr;</span>').Append((ConvertTo-PpaHtmlText ([string]$f.toStatus))).AppendLine('</td></tr>')
            }
            [void]$sb.AppendLine('    </tbody></table>')
        }

        [void]$sb.AppendLine('  </div></div>')
    }

    [void]$sb.AppendLine('  <div class="foot">CAMP v2 delta &middot; offline comparison of two read-only snapshots. Object changes reflect configuration metadata only; statuses are inputs to consultant judgment, not compliance determinations.</div>')
    [void]$sb.AppendLine('</div></body></html>')

    $html = $sb.ToString()
    Clear-PpaRedaction
    return $html
}
