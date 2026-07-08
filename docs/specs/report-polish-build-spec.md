# CAMP v2 — Report Polish & Remediation Snippets (Wave 3)

**Audience:** Claude Code, implementing against the `camp-v2-report-first` branch.
**Nature of this wave:** Render-layer, entry-script parameters, and check-catalog
metadata only. **Zero collector changes, zero new cmdlets, zero live-tenant
dependency.** Everything in this wave is built and validated on this machine
using the fixture and render-smoke-test infrastructure from the previous wave.

---

## Global rules

1. **Do not modify** any collector, analyzer logic, severity assignment, or
   Wave 2 finding behavior. If a bug is discovered in those layers while
   working, report it in the final summary — do not fix it silently.
2. **Single-file output preserved.** The report remains one self-contained
   HTML file. No new external/CDN dependencies; all new JS is vanilla and
   inline, all new CSS follows the existing visual language (full-width
   Bootstrap skin, Microsoft-blue cards, colored callouts, collapsible
   drill-downs). New features must look native, not bolted on.
3. **Keyed to the catalog.** Anywhere a feature references findings, key off
   the existing check IDs from CHECK_CATALOG (e.g., AI-02, IRM-03), never
   positional indices. Update CHECK_CATALOG.md where this wave adds metadata.
4. **Graceful absence.** Every feature must render correctly when its inputs
   are sparse: an exec summary over a nearly-empty tenant, filters over three
   findings, remediation blocks when no snippet is defined. The sparse
   fixture is the regression case for all of it.
5. **Commit per feature** (P1–P8 below map roughly one-to-one), clear messages.

---

## P1 — Executive summary (page one)

- Rendered at the **top of the existing HTML report**, before the first
  section, in the established visual style.
- Contents:
  - Run metadata line: tool name/version, run timestamp, tenant hint
    (suppressed under redaction, see P6).
  - Severity count tiles or a compact count row: Recommendations,
    Improvements, OK, Informational — counts must be computed from the same
    finding objects the body renders (single source of truth; add a test
    asserting summary counts equal body counts).
  - "Top findings" list: every Recommendation, then every Improvement, one
    line each (check ID + finding title + section name), each line an anchor
    link (P4) to the full finding. If the combined list exceeds ~15 entries,
    cap at 15 with a "+N more below" line.
- Prints as page one under the P3 stylesheet.

## P2 — Client-side severity filters + text search

- A slim control bar (sticky or top-of-body, whichever fits the existing
  skin better) with:
  - Toggle chips for each severity (OK / Improvement / Recommendation /
    Informational), all on by default.
  - A free-text search box filtering finding cards by title + visible body
    text (case-insensitive substring is sufficient; no fuzzy matching).
  - A reset control.
- Behavior: non-matching finding cards hide; a section whose findings are all
  hidden collapses to its header with a "(n findings hidden by filter)" note
  rather than vanishing entirely. Filtering must not break the existing
  collapsible drill-downs, and drill-down open/closed state should survive
  filter toggling.
- Pure vanilla JS, inline, no dependencies.

## P3 — Print / PDF stylesheet

- `@media print` rules:
  - Expand all collapsible drill-downs for print (or provide a "prepare for
    print" toggle that expands them — implementer's choice, but printed
    output must contain drill-down content).
  - Hide the P2 filter controls and any interactive-only affordances.
  - Page-break rules: avoid splitting a finding card across pages where
    feasible; each top-level section starts cleanly.
  - Preserve severity colors (`print-color-adjust: exact` where supported).
  - Exec summary is page one; keep its layout print-stable.

## P4 — Per-finding anchors

- Every finding card gets a stable `id` derived from its check ID (stable
  across runs by construction). A small link affordance (e.g., a ¶ or link
  icon on hover) copies/navigates to the anchor.
- Add a test asserting anchor IDs are unique across the rendered report for
  both fixtures.

## P5 — Run profile: section include/exclude

- Entry-script parameters: `-ExcludeSection <string[]>` and
  `-IncludeSection <string[]>` (include, when supplied, means "only these"),
  operating on the existing top-level section keys. Optionally also
  `-Profile <path>` accepting a small psd1/JSON file expressing the same —
  implement the parameters first; the file form is nice-to-have.
- Default remains all sections on.
- Excluded sections are omitted from the body entirely, and a single footer
  line lists them: "Sections excluded by run profile: X, Y" — a thin report
  must never look like a silent failure. The exec summary counts reflect
  only included sections.

## P6 — Redaction mode

- `-Redact` switch on the entry script. Applied at **render time only** —
  finding data in memory is untouched; implement as a single redaction
  function applied at the display boundary so coverage is consistent and
  testable.
- Default `-Redact` scope: tenant domains (including *.onmicrosoft.com
  strings), UPNs/email addresses, and the tenant hint in the exec summary
  header. Replacement should be a stable mask (e.g., `[redacted-domain]`,
  `user01@[redacted]` with stable numbering within a run so the report stays
  internally consistent).
- Stricter opt-in: `-RedactNames` additionally pseudonymizes policy/label
  names as stable tokens (`Policy-01`, `Label-03` …), consistent everywhere
  the same name appears, including inside remediation snippet text.
- A visible banner on the report notes REDACTED mode and its scope.
- Fixtures must contain a fake UPN, a fake tenant domain, and a policy name
  so tests can assert masking actually occurs (and does NOT occur when the
  switch is absent).

## P7 — Remediation snippets

- **Catalog structure:** each check in CHECK_CATALOG may define an optional
  remediation block: `portalPath` (string), `cmdlet` (optional string),
  `learnUrl` (string, may reuse the finding's existing Learn link).
- **Rendering:** inside the finding card, shown only when the finding's
  status is Improvement or Recommendation. Collapsible "How to remediate"
  region: portal path as text, cmdlet in a code block with a copy-to-
  clipboard button (vanilla JS), Learn link. Under `-RedactNames`, any
  policy names inside snippet text are pseudonymized consistently (P6).
- **Content sourcing rule (non-negotiable):**
  - Cmdlet snippets may ONLY be drafted where groundable: cmdlets and
    parameters verified in this project's probe/spec work (e.g.,
    `Set-DlpCompliancePolicy -Identity "<name>" -Mode Enable` for the
    simulation-mode finding), or long-established well-known cmdlets, or
    usage documented at the finding's own Learn link.
  - Where there is any uncertainty about a cmdlet or parameter name: provide
    `portalPath` + `learnUrl` only. Never invent or guess cmdlet syntax.
  - The tool remains read-only: snippets are displayed text, never executed.
- **Human review pass:** generate `docs/REMEDIATION_REVIEW.md` — a checklist
  listing every check ID with a drafted snippet, its cmdlet (if any), and a
  review checkbox. Every drafted snippet is a DRAFT until the human reviews
  it; say so at the top of that file. Draft for every existing check where
  grounding exists, portal-path-only elsewhere; do not leave the structure
  empty just because content is editorial.

## P8 — Fixtures, tests, and the DEV validation loop

- Extend the fixture set with (or ensure there is) a **dense/populated
  tenant fixture**: enough finding variety to exercise every severity, every
  section, the exec-summary cap (>15 Recommendations+Improvements), filters,
  anchors, redaction targets, and at least several remediation-bearing
  findings. Keep the sparse fixture as-is for the graceful-absence cases.
- Pester coverage for this wave (extend the existing suite):
  - Exec summary counts equal body finding counts, both fixtures.
  - Anchor IDs unique, both fixtures.
  - Profile exclusion removes sections from body and lists them in footer;
    summary counts adjust.
  - Redaction masks the planted UPN/domain (and names under `-RedactNames`),
    and does not mask when switches are absent.
  - Remediation blocks render only on Improvement/Recommendation, and only
    where defined.
- **`tools/Build-SampleReports.ps1`** (or matching existing conventions): a
  one-command script that renders the report from both fixtures — plus one
  redacted variant and one profile-filtered variant — into a local,
  gitignored output folder, printing the file paths at the end. This is the
  human's browser-based validation loop on this machine; treat it as a
  first-class deliverable.

---

## Deliverables checklist

- Renderer + entry-script changes for P1–P6.
- CHECK_CATALOG remediation metadata + rendered remediation UI (P7).
- `docs/REMEDIATION_REVIEW.md` draft-review checklist.
- Dense fixture + expanded Pester suite (P8), all tests passing.
- `tools/Build-SampleReports.ps1` producing openable sample HTML files.
- README: brief documentation of `-ExcludeSection` / `-IncludeSection` /
  `-Profile` / `-Redact` / `-RedactNames` and the sample-report script.

## Out of scope for this wave

- Coverage matrix, JSON snapshot, delta mode (later waves).
- Any collector/analyzer/severity change; any new cmdlet; Microsoft Graph.
- Executing remediation content in any form.
