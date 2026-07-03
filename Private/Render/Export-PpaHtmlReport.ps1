# Export-PpaHtmlReport.ps1 - turns a normalized posture object into the HTML report.
# The HTML report is the primary deliverable (report-first). Depends on PpaHtml.ps1.
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function Export-PpaHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Normalized,
        [switch] $IsSample,
        # Titles of sections removed by the run profile (P5) - rendered as a single
        # footer line so a thin report never looks like a silent failure.
        [string[]] $ExcludedSections = @(),
        # P6 render-time redaction. -RedactNames implies -Redact and additionally
        # pseudonymizes policy/label names. Applied at the display boundary only;
        # the normalized object and the JSON export are never modified.
        [switch] $Redact,
        [switch] $RedactNames
    )

    # Defensive: never inherit redaction state from a previous render (a failed
    # render cannot poison the next one - the next call always resets first).
    Clear-PpaRedaction
    if ($Redact -or $RedactNames) {
        Initialize-PpaRedaction -Normalized $Normalized -RedactNames:$RedactNames
    }

    $meta      = $Normalized.meta
    $lic       = $Normalized.licensing
    $sections  = @($Normalized.sections)
    $sb        = New-Object System.Text.StringBuilder

    # P7: static remediation-snippet map, joined per finding by check ID at render time.
    $remedCatalog = Get-PpaRemediationCatalog

    # Group-by-first-appearance + all-solutions totals, computed once from the same
    # finding objects the body renders. Shared by the posture summary (P1) and the
    # Solutions Summary so their counts can never drift apart.
    $groupOrder = New-Object System.Collections.Generic.List[string]
    $groupMap   = @{}
    $groupMeta  = @{}
    $totals     = [ordered]@{ 'OK'=0; 'Improvement'=0; 'Recommendation'=0; 'Informational'=0; 'Verify manually'=0 }
    foreach ($sec in $sections) {
        $gname = [string]$sec.group
        if (-not $groupMap.ContainsKey($gname)) {
            $groupMap[$gname]  = New-Object System.Collections.Generic.List[object]
            $groupMeta[$gname] = [pscustomobject]@{ Icon = [string]$sec.groupIcon; Tag = [string]$sec.groupTag }
            $groupOrder.Add($gname)
        }
        $groupMap[$gname].Add($sec)
        $cts = Get-PpaSectionCounts $sec
        foreach ($st in $script:PpaStatusOrder) { $totals[$st] = [int]$totals[$st] + [int]$cts[$st] }
    }

    # ---- document head + navbar ----
    [void]$sb.AppendLine((Get-PpaReportHead))
    if ($IsSample) {
        [void]$sb.AppendLine('<div class="mock-flag">Illustrative sample data &middot; fictional tenant (Northwind Health) &middot; rendered from Samples/sample-normalized.json</div>')
    }
    if ($Redact -or $RedactNames) {
        $scope = 'tenant domains, UPNs and email addresses masked'
        if ($RedactNames) { $scope += ' &middot; policy and label names pseudonymized' }
        [void]$sb.Append('<div class="redact-flag">REDACTED report &middot; ').Append($scope).AppendLine(' &middot; masking applied at render time only</div>')
    }
    [void]$sb.AppendLine((Get-PpaNavbarHtml))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('<div class="app-body p-3"><main class="main">')
    [void]$sb.AppendLine('')

    # ---- title card ----
    [void]$sb.AppendLine('  <div class="card"><div class="card-body">')
    [void]$sb.AppendLine('    <div class="row">')
    [void]$sb.AppendLine('      <div class="col">')
    [void]$sb.Append('        <h2 class="card-title">').Append((ConvertTo-PpaHtmlText $meta.reportTitle)).AppendLine('</h2>')
    [void]$sb.Append('        <strong>Version ').Append((ConvertTo-PpaHtmlText $meta.version)).Append(' &middot; ').Append((ConvertTo-PpaHtmlText $meta.versionDate)).AppendLine('</strong>')
    [void]$sb.AppendLine('        <p>Reads your Microsoft Purview configuration and summarizes current posture across data protection, governance,')
    [void]$sb.AppendLine('           insider risk, discovery, and AI &mdash; an input to consultant judgment, not a compliance determination.')
    [void]$sb.AppendLine('           <em>Click any finding to drill down to the enumerated detail.</em></p>')
    [void]$sb.AppendLine('        <table>')
    [void]$sb.Append('          <tr><td><strong>Date</strong></td><td><strong>:&nbsp; ').Append((ConvertTo-PpaHtmlText $meta.dateDisplay)).AppendLine('</strong></td></tr>')
    [void]$sb.Append('          <tr><td><strong>Organization &nbsp;</strong></td><td><strong>:&nbsp; ').Append((ConvertTo-PpaHtmlText $meta.organization)).AppendLine('</strong></td></tr>')
    [void]$sb.Append('          <tr><td><strong>Tenant &nbsp;</strong></td><td><strong>:&nbsp; ').Append((ConvertTo-PpaHtmlText $meta.tenant)).AppendLine('</strong></td></tr>')
    [void]$sb.Append('          <tr><td><strong>Operator &nbsp;</strong></td><td><strong>:&nbsp; ').Append((ConvertTo-PpaHtmlText $meta.operator)).AppendLine('</strong></td></tr>')
    [void]$sb.Append('          <tr><td><strong>Mode &nbsp;</strong></td><td><strong>:&nbsp; ').Append((ConvertTo-PpaHtmlText $meta.mode)).AppendLine('</strong></td></tr>')
    [void]$sb.AppendLine('        </table>')
    [void]$sb.AppendLine('      </div>')
    [void]$sb.AppendLine('      <div class="col-auto"><div class="logo-ph">Client logo (250&times;150)</div></div>')
    [void]$sb.AppendLine('    </div>')

    # No license banner in the report (client-facing polish): the E5 assumption and its
    # caveats live in the README pre-requisite note and LIMITATIONS.md. The normalized
    # object's licensing.note still travels in the JSON export for downstream context.
    [void]$sb.AppendLine('  </div></div>')
    [void]$sb.AppendLine('')

    # ---- posture summary (P1: page one, before the first section) ----
    [void]$sb.AppendLine((Write-PpaPostureSummary -Meta $meta -Sections $sections -Totals $totals))
    [void]$sb.AppendLine('')

    # ---- filter bar (P2: sticky severity chips + text search; hidden in print) ----
    [void]$sb.AppendLine((Write-PpaFilterBar))
    [void]$sb.AppendLine('')

    # ---- environment at a glance ----
    [void]$sb.AppendLine('  <div class="card mt-3 glance">')
    [void]$sb.AppendLine('    <div class="card-header"><strong>Environment at a glance</strong></div>')
    [void]$sb.AppendLine('    <div class="card-body">')
    [void]$sb.AppendLine('      <div class="row" style="row-gap:10px;">')
    foreach ($sec in $sections) {
        $g = $sec.glance
        $dot = (Get-PpaStatusStyle $g.status).Dot
        [void]$sb.Append('        <div class="col-6 col-md-3"><a class="cell" href="#').Append((ConvertTo-PpaHtmlAttr $sec.id)).Append('">')
        [void]$sb.Append('<div class="nm"><span class="gdot ').Append($dot).Append('"></span>').Append((ConvertTo-PpaHtmlText $g.name)).Append('</div>')
        [void]$sb.Append('<div class="mx">').Append((ConvertTo-PpaHtmlText $g.metric)).Append('</div>')
        [void]$sb.Append('<div class="sub">').Append((ConvertTo-PpaHtmlText $g.sub)).AppendLine('</div></a></div>')
    }
    [void]$sb.AppendLine('      </div>')
    [void]$sb.AppendLine('    </div>')
    [void]$sb.AppendLine('  </div>')
    [void]$sb.AppendLine('')

    # ---- solutions summary (group/totals computed once, above) ----
    [void]$sb.AppendLine('  <div class="card mt-3" id="Solutionsummary">')
    [void]$sb.AppendLine('    <div class="card-header"><strong>Solutions Summary</strong></div>')
    [void]$sb.AppendLine('    <div class="card-body">')
    [void]$sb.AppendLine('      <table class="table table-borderless summary" style="margin-bottom:.5rem;">')
    [void]$sb.AppendLine('        <tbody>')
    [void]$sb.AppendLine('          <tr style="border-bottom:2px solid #d7e0ea;">')
    [void]$sb.AppendLine('            <td width="20"><i class="fas fa-user-cog"></i></td>')
    [void]$sb.AppendLine('            <td><strong>All Solutions</strong></td>')
    [void]$sb.Append('            <td align="right">').Append((Write-PpaSummaryCountCells $totals)).AppendLine('</td>')
    [void]$sb.AppendLine('          </tr>')
    [void]$sb.AppendLine('')
    foreach ($gname in $groupOrder) {
        $gm = $groupMeta[$gname]
        $parentText = ConvertTo-PpaHtmlText $gname
        if (-not [string]::IsNullOrEmpty($gm.Tag)) {
            $parentText += ' <span style="font-weight:600; font-size:11px; color:#0078D4;">&nbsp;' + (ConvertTo-PpaHtmlText $gm.Tag) + '</span>'
        }
        [void]$sb.Append('          <tr class="ssparent"><td width="20"><i class="').Append((ConvertTo-PpaHtmlAttr $gm.Icon)).Append('"></i></td><td colspan="2">').Append($parentText).AppendLine('</td></tr>')
        foreach ($sec in $groupMap[$gname]) {
            $cts = Get-PpaSectionCounts $sec
            [void]$sb.Append('          <tr class="sschild"><td></td><td><a href="#').Append((ConvertTo-PpaHtmlAttr $sec.id)).Append('">').Append((ConvertTo-PpaHtmlText $sec.title)).AppendLine('</a></td>')
            [void]$sb.Append('            <td align="right">').Append((Write-PpaSummaryCountCells $cts)).AppendLine('</td></tr>')
        }
    }
    [void]$sb.AppendLine('        </tbody>')
    [void]$sb.AppendLine('      </table>')
    [void]$sb.AppendLine('      <div style="font-size:13px; text-align:right;">')
    [void]$sb.AppendLine('        <span class="badge badge-success" style="padding:5px;">&nbsp;</span> OK &nbsp;')
    [void]$sb.AppendLine('        <span class="badge badge-warning" style="padding:5px;">&nbsp;</span> Improvement &nbsp;')
    [void]$sb.AppendLine('        <span class="badge badge-info" style="padding:5px;">&nbsp;</span> Recommendation &nbsp;')
    [void]$sb.AppendLine('        <span class="badge badge-secondary" style="padding:5px;">&nbsp;</span> Informational &nbsp;')
    [void]$sb.AppendLine('        <span class="badge badge-dark" style="padding:5px;">&nbsp;</span> Verify manually')
    [void]$sb.AppendLine('      </div>')
    [void]$sb.AppendLine('    </div>')
    [void]$sb.AppendLine('  </div>')
    [void]$sb.AppendLine('')

    # ---- section cards ----
    foreach ($sec in $sections) {
        $counts = Get-PpaSectionCounts $sec
        [void]$sb.Append('  <div class="card mt-3 seccard" id="').Append((ConvertTo-PpaHtmlAttr $sec.id)).AppendLine('">')
        [void]$sb.AppendLine('    <div class="card-header"><div class="row">')
        [void]$sb.Append('      <div class="col-sm" style="margin:auto 0;"><a>').Append((ConvertTo-PpaHtmlText $sec.title)).Append('</a>')
        [void]$sb.AppendLine('<span class="sec-hiddennote"></span></div>')
        [void]$sb.AppendLine('      <div class="col-sm text-right" style="padding-right:10px;">')
        [void]$sb.Append('        ').AppendLine((Write-PpaCountBadges $counts))
        [void]$sb.AppendLine('      </div></div></div>')
        [void]$sb.AppendLine('    <div class="card-body" style="padding-top:4px;">')
        [void]$sb.AppendLine('')

        foreach ($f in @($sec.findings)) {
            $s = Get-PpaStatusStyle $f.status
            # Stable per-finding anchor derived from the check ID (never positional).
            # data-status feeds the P2 client-side severity filter.
            $anchorId = 'finding-' + (ConvertTo-PpaHtmlAttr $f.id)
            [void]$sb.Append('      <div class="finding" id="').Append($anchorId).Append('" data-status="').Append((ConvertTo-PpaHtmlAttr $f.status)).AppendLine('">')
            [void]$sb.Append('        <div class="row finding-head" data-toggle="collapse" data-target="#').Append((ConvertTo-PpaHtmlAttr $f.domId)).AppendLine('" aria-expanded="false">')
            [void]$sb.Append('          <div class="col-sm-10"><i class="fas fa-chevron-right chev"></i><h6>').Append((ConvertTo-PpaHtmlText $f.title)).Append('</h6>')
            [void]$sb.Append('<a class="anchor-link" href="#').Append($anchorId).AppendLine('" title="Copy link to this finding">&para;</a></div>')
            [void]$sb.Append('          <div class="col-sm-2 text-right"><span class="badge ').Append($s.Badge).Append('">').Append((ConvertTo-PpaHtmlText $f.status)).AppendLine('</span></div>')
            [void]$sb.AppendLine('        </div>')
            # Note: findings may carry a 'requires' tier annotation; it travels in the JSON
            # export only and is deliberately NOT rendered (client-facing polish - the E5
            # assumption is documented in the README, not the report).
            [void]$sb.Append('        <div class="collapse" id="').Append((ConvertTo-PpaHtmlAttr $f.domId)).Append('"><div class="bd-callout ').Append($s.Callout).AppendLine('">')
            [void]$sb.Append('          <p class="whyline">').Append((ConvertTo-PpaHtmlText $f.whyline)).AppendLine('</p>')
            $tableHtml = Write-PpaDetailTable $f.table
            if ($tableHtml) { [void]$sb.Append($tableHtml) }
            # P7: remediation only where the finding is actionable AND the catalog
            # defines an entry for this check ID (keyed join, never positional).
            if ($f.status -eq 'Improvement' -or $f.status -eq 'Recommendation') {
                $remedHtml = Write-PpaRemediation (Get-PpaRemediation -Catalog $remedCatalog -CheckId ([string]$f.id))
                if ($remedHtml) { [void]$sb.Append($remedHtml) }
            }
            $lmHtml = Write-PpaLearnMore $f.learnmore
            if ($lmHtml) { [void]$sb.Append($lmHtml) }
            [void]$sb.AppendLine('        </div></div>')
            [void]$sb.AppendLine('      </div>')
            [void]$sb.AppendLine('')
        }

        [void]$sb.AppendLine('      <div class="text-right backlink" style="padding:8px 10px 0;"><a href="#Solutionsummary">Go to Solutions Summary</a></div>')
        [void]$sb.AppendLine('    </div>')
        [void]$sb.AppendLine('  </div>')
        [void]$sb.AppendLine('')
    }

    # ---- observations ----
    $obs = @($Normalized.observations)
    if ($obs.Count -gt 0) {
        [void]$sb.AppendLine('  <div class="card mt-3">')
        [void]$sb.AppendLine('    <div class="card-header"><strong>Observations</strong></div>')
        [void]$sb.AppendLine('    <div class="card-body">')
        [void]$sb.AppendLine('      <p style="margin-bottom:.5rem;">Advisory only &mdash; for the consultant to weigh against engagement context, licensing, and stakeholder input. Not decisions, not a remediation plan.</p>')
        foreach ($o in $obs) {
            [void]$sb.Append('      <div class="bd-callout bd-callout-info"><h5>').Append((ConvertTo-PpaHtmlText $o.title)).AppendLine('</h5>')
            foreach ($p in @($o.points)) {
                if (-not [string]::IsNullOrEmpty($p.lead)) {
                    [void]$sb.Append('        <p><strong>').Append((ConvertTo-PpaHtmlText $p.lead)).Append('</strong> ').Append((ConvertTo-PpaHtmlText $p.text)).AppendLine('</p>')
                } else {
                    [void]$sb.Append('        <p>').Append((ConvertTo-PpaHtmlText $p.text)).AppendLine('</p>')
                }
            }
            [void]$sb.AppendLine('      </div>')
        }
        [void]$sb.AppendLine('    </div>')
        [void]$sb.AppendLine('  </div>')
        [void]$sb.AppendLine('')
    }

    # ---- run-profile note (P5): a thin report must never look like a silent failure ----
    $excludedList = @($ExcludedSections | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($excludedList.Count -gt 0) {
        [void]$sb.Append('  <p class="profile-note">Sections excluded by run profile: ')
        [void]$sb.Append((ConvertTo-PpaHtmlText ($excludedList -join ', '))).AppendLine('</p>')
        [void]$sb.AppendLine('')
    }

    # ---- close + footer ----
    [void]$sb.AppendLine('</main></div>')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine((Get-PpaPolishScript))
    [void]$sb.AppendLine((Get-PpaFooterHtml))

    Clear-PpaRedaction
    return $sb.ToString()
}
