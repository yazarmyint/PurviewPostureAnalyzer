# PLAN.md — CAMP v2 / Purview Posture Analyzer

One planning document. Read it, mark it up, and we build from it. Nothing in the source
tree changes until you approve this.

**Guiding sentence (every decision serves this):** *what a June 2026 CAMP should care about,
delivered as a report a consultant hands to their delivery team at engagement kickoff.*

**The two fixed targets win over this plan:** the original design mock (look + content)
and `CHECK_CATALOG.md` (the checks). If anything below diverges from them, they are right and
this document is wrong.

---

## 1. What I read, and the model it implies

I read both spec files in full and reconciled them against each other. Three structural facts
drive the whole design:

1. **Finding-level status is the atom.** Every badge, every count, the Solutions Summary, and
   the at-a-glance dots are all derived from one status per finding. I summed the mock by hand:
   the eight sections contain **22 findings** whose statuses total **OK 2 · Improvement 7 ·
   Recommendation 3 · Informational 9 · Verify 1** — exactly the "All Solutions" row. So counts
   are *computed from findings*, never authored separately.

2. **A finding owns one status; its drill-down table can show many.** DLP-01 ("6 DLP policies
   exist") is a single **Informational** finding, but its table lists rows that are individually
   OK or Improvement. Row status is presentation inside the table; it does not roll up into the
   counts.

3. **Remarks are attached to a row, not to the table.** The grey `remarks` line renders directly
   after the data row it belongs to (DLP-01 has a remark sitting *between* two data rows). So in
   the data model a row optionally carries a `remark` string.

This is why the build is **report-first**: the finding object is the design center, the HTML is
its primary rendering, and JSON is the same objects serialized.

---

## 2. Architecture — the pipeline

```
Connect ──► Collect ──► Analyze ──► Assemble ──► Render
(sessions)  (raw       (raw ->      (sections +   (HTML primary)
            per         findings     computed      (JSON export,
            section)    w/ status)   counts +      same objects)
                                     glance)
```

- **Collect** calls `Get-*` only and returns a raw, un-judged object per section (plus one
  error record if the collector failed). One collector failing never stops the run.
- **Analyze** turns raw data into **finding objects** and assigns the status per
  `CHECK_CATALOG.md`. Analyzers are pure functions of their raw input, so they can be unit-tested
  against a fixture with no tenant.
- **Assemble** (`ConvertTo-PpaNormalized`) gathers findings into sections, computes the status
  counts and the at-a-glance headline, and produces the single **normalized object**.
- **Render** walks the normalized object. `Export-PpaHtmlReport` is the heart of v1;
  `Export-PpaJson` serializes the same object.

**Why this shape (plain-language):** collectors, analyzers, and the renderer are separated so
that (a) the renderer can be built and proven against sample data *before any tenant call exists*,
and (b) the status logic can be tested without a live connection. The static per-check content
(the "why this matters" line, the Learn-more links, the table column headers) lives in a **check
catalog data file**, so analyzers only decide status and fill in the dynamic numbers.

---

## 3. Module structure (lean, conventional PowerShell module)

```
PurviewPostureAnalyzer.psd1              # manifest (exports the 3 public functions)
PurviewPostureAnalyzer.psm1              # dot-sources Private/**, exports Public/**

Public/
  Invoke-PurviewPostureAnalyzer.ps1      # entry point: connect->collect->analyze->assemble->render
  Connect-PurviewPostureSession.ps1      # Connect-IPPSSession / -ExchangeOnline / -MgGraph
  Disconnect-PurviewPostureSession.ps1

Private/
  Render/
    Export-PpaHtmlReport.ps1             # normalized object -> HTML string (the v1 centerpiece)
    Export-PpaJson.ps1                   # normalized object -> JSON export
    PpaHtml.ps1                          # small helpers: status->css, badge, table row, learnmore, encode
  Model/
    New-PpaFinding.ps1                   # finding factory + status validation
    ConvertTo-PpaNormalized.ps1          # assemble sections, compute counts + glance headline
  Collect/
    Invoke-PpaReadCmdlet.ps1             # read-only wrapper: runs a Get-*, captures errors, never throws
    Get-PpaLicensing.ps1                 # licensing / Copilot presence (drives every E5 gate)
    Get-PpaSensitivityLabels.ps1
    Get-PpaDlp.ps1
    Get-PpaRetention.ps1
    Get-PpaInsiderRisk.ps1
    Get-PpaAudit.ps1
    Get-PpaEdiscovery.ps1
    Get-PpaCommsCompliance.ps1
    Get-PpaDspmAi.ps1
  Analyze/
    Invoke-PpaLabelAnalyzer.ps1          # one analyzer per section: raw -> findings
    Invoke-PpaDlpAnalyzer.ps1
    Invoke-PpaRetentionAnalyzer.ps1
    Invoke-PpaInsiderRiskAnalyzer.ps1
    Invoke-PpaAuditAnalyzer.ps1
    Invoke-PpaEdiscoveryAnalyzer.ps1
    Invoke-PpaCommsComplianceAnalyzer.ps1
    Invoke-PpaDspmAiAnalyzer.ps1

Data/
  checks.json                            # static per-check content: title, whyline, columns,
                                         #   learn-more links, parent group  (transcribed from CHECK_CATALOG.md)
Samples/
  sample-normalized.json                 # the Northwind Health fixture from the mock (built FIRST)
  sample-raw/                            # per-section raw fixtures (added in Phase 3 for analyzer tests)
Tests/
  ReadOnlyGuard.Tests.ps1                # fails if any mutating verb appears in Collect/ or Analyze/
  Analyzer.Tests.ps1                     # raw fixture -> expected statuses
  Render.Tests.ps1                       # sample-normalized -> HTML contains expected markers
docs/
  PERMISSIONS.md  WHAT-IS-COLLECTED.md  INTERPRETING-RESULTS.md  LIMITATIONS.md
PLAN.md   README.md   LICENSE   NOTICE
```

The prior attempt's `Private/**` tree is staged for deletion in git; this replaces it. The MIT
`LICENSE`/`NOTICE` attribution for reused CAMP code stays.

---

## 4. The normalized data shape (feeds the renderer)

This is the contract between "everything upstream" and the renderer. `Samples/sample-normalized.json`
is exactly this shape, populated with the mock's Northwind Health data.

```jsonc
{
  "meta": {
    "reportTitle": "Configuration Analyzer for Microsoft Purview",
    "version": "2.0", "versionDate": "June 2026",
    "dateDisplay": "24-Jun-2026 14:07 UTC",
    "organization": "Northwind Health",
    "tenant": "northwindhealth.onmicrosoft.com",
    "operator": "consultant@kizan (Compliance Reader)",
    "mode": "Read-only · configuration metadata only"
  },
  "licensing": {
    "summary": "Microsoft 365 E3 + Enterprise Mobility + Security E5",
    "e5Compliance": false,          // gates IRM / CC / Audit Premium / eDiscovery Premium
    "copilot": true,                // gates the DSPM-for-AI section verdicts
    "banner": "Insider Risk, Communication Compliance, Audit Premium and eDiscovery Premium ..."
  },
  "sections": [
    {
      "id": "Sensitivity_Labels",           // anchor used by glance + summary links
      "title": "Sensitivity Labels",
      "group": "Microsoft Information Protection",   // parent row in Solutions Summary
      "groupIcon": "fa-shield-alt",
      "glance": { "status": "Improvement", "metric": "5 labels", "sub": "2 policies · auto-label in sim" },
      "findings": [
        {
          "id": "LABELS-01",
          "domId": "f-lab-1",
          "title": "Taxonomy is defined",
          "status": "Informational",         // the ONLY status that counts
          "whyline": "A clear, ordered taxonomy is the foundation ...",
          "table": {
            "columns": ["Label", "Priority", "Scope", "Status"],
            "rows": [
              { "cells": ["Public", "0", "Files, Emails"], "status": "Informational" },
              { "cells": ["↳ Highly Confidential \\ Legal", "3.1", "Files"],
                "status": "Informational", "indent": true }
            ]
          },
          "learnmore": [
            { "label": "Microsoft Purview portal — Information Protection",
              "url": "https://purview.microsoft.com", "tag": "portal" },
            { "label": "Overview of sensitivity labels",
              "url": "https://learn.microsoft.com/en-us/purview/sensitivity-labels", "tag": "docs" }
          ]
        }
      ]
    }
  ],
  "observations": [
    { "title": "DLP looks broader than it enforces",
      "body": ["6 policies read as substantial coverage, but 2 never left test mode ...",
               "→ Worth confirming which locations the client believes are protected ..."] }
  ]
}
```

### Finding object schema (the atom)

| field       | type            | notes |
|-------------|-----------------|-------|
| `id`        | string          | stable check id from the catalog (`LABELS-01`), used in code + JSON |
| `domId`     | string          | collapse target id (`f-lab-1`) |
| `title`     | string          | the finding-head heading |
| `status`    | enum            | `OK` / `Improvement` / `Recommendation` / `Informational` / `Verify manually` |
| `whyline`   | string          | the one-line "why it matters" above the table |
| `table`     | object \| null  | `{ columns[], rows[] }`; **null** for advisory findings with no table (e.g. IRM-02) |
| `table.rows[].cells` | string[] | one per column except the trailing Status column |
| `table.rows[].status` | enum    | row-level display status |
| `table.rows[].remark` | string? | optional; renders as a full-width `remarks` row after this row |
| `table.rows[].indent` | bool?   | sub-label / hierarchical indent |
| `learnmore` | array           | `{ label, url, tag }`; `tag` is `portal` or `docs` |

**Computed, never authored:** section status counts, the Solutions Summary parent/child rows and
the "All Solutions" totals, and the section-header badges — all derived by `ConvertTo-PpaNormalized`
from `findings[].status`.

---

## 5. Status model and its visual mapping

Five statuses (from the mock/catalog). `Verify manually` is reserved for the genuinely
un-assertable from a session (only AUD-02 uses it in the mock). E5 features on a sub-E5 tenant are
**Informational (not licensed)** — never a gap.

| Status            | header/finding badge | drill-down callout    | glance dot | in-row icon |
|-------------------|----------------------|-----------------------|-----------|-------------|
| OK                | `badge-success`      | `bd-callout-success`  | `ok`      | `fa-check-circle text-success` |
| Improvement       | `badge-warning`      | `bd-callout-warning`  | `impr`    | `fa-times-circle text-danger` |
| Recommendation    | `badge-info`         | `bd-callout-info`     | `rec`     | `fa-info-circle text-muted` |
| Informational     | `badge-secondary`    | `bd-callout-secondary`| `info`    | *(plain text, no icon)* |
| Verify manually   | `badge-dark`         | `bd-callout-dark`     | `verify`  | `fa-user-check text-secondary` |

- **Section header** shows only non-zero counts, e.g. `OK 1  Improvement 1  ...` (`Verify` uses
  the short label in the header, matching the mock).
- **Solutions Summary** shows all five counts including zeros, as fixed-width `sscount` badges.
- **At-a-glance dot** = the section's headline status. Default rule:
  `Improvement > Recommendation > OK > Informational > Verify`, but a section may override its
  headline explicitly (Audit's headline is **OK** — "logging is on" — even though it also carries
  a Verify). The metric (`mx`) and sub-line are composed by the section assembler from the raw
  counts. For sample data these are authored to match the mock verbatim.

---

## 6. Renderer plan (reproducing the mock region by region)

`Export-PpaHtmlReport` builds the HTML as a string (the legacy CAMP approach; no template engine
needed). It emits, in order:

1. **Head + `<style>`** — copied verbatim from the mock.
2. **Navbar** — static, minus the "DESIGN MOCK" flag banner (that banner is dropped in the real
   report; a subtle "illustrative data" note only appears when rendering the sample fixture).
3. **Title card** — from `meta`; the licensing `alert-info` banner from `licensing`.
4. **Environment at a glance** — one cell per section from `section.glance` (dot class from status,
   `metric`, `sub`, anchor = `section.id`).
5. **Solutions Summary** — group sections by `group`, emit parent rows + child rows with the five
   `sscount` badges, and the "All Solutions" totals; then the legend.
6. **Section cards** — for each section: header (title + non-zero count badges); then each finding
   as a collapsible `finding` (chevron + title + status badge, and a `bd-callout-*` body with the
   whyline, the detail table, per-row remarks, and the learnmore block); then the "Go to Solutions
   Summary" link.
7. **Observations** — from `observations[]`.
8. **Footer** — the read-only disclaimer, verbatim.

Small helpers in `PpaHtml.ps1`: `Get-PpaStatusClass`, `Write-PpaBadge`, `Write-PpaDetailTable`,
`Write-PpaLearnMore`, and an HTML-encoder. **All output uses HTML entities** (`&mdash;`, `&middot;`,
`&#8627;`) exactly as the mock does, which keeps the emitted source ASCII and safe under Windows
PowerShell 5.1 (per the encoding note in project memory).

**Fidelity check (Phase 2 of the build):** render `sample-normalized.json` and diff visually
against the original design mock region by region — the enumerated tables, the Solutions
Summary counts, the at-a-glance strip, the drill-down links — and fix until it matches.

> **Decision D1 (settled) — CDN assets, match the mock exactly.** The report loads Bootstrap,
> Font Awesome, jQuery and Popper from the same CDNs as the original design mock, byte-for-byte.
> Fidelity to the mock wins here. (Self-contained/offline rendering is noted as a possible Phase 2
> option if a client environment ever needs it, but v1 does not build it.)

---

## 7. v1 collectors and the cmdlets they read

Eight sections plus a licensing collector. `✓` = verified in original CAMP or on Microsoft Learn;
`⚠` = newer surface I will confirm against current `learn.microsoft.com` **before the collector
that relies on it is trusted** (Phase 3), per the guardrail.

| Section | Collector | Reads |
|---------|-----------|-------|
| Licensing | `Get-PpaLicensing` | Graph `Get-MgSubscribedSku` service plans ⚠ (E5 compliance + Copilot plan id) |
| 01 Labels | `Get-PpaSensitivityLabels` | `Get-Label` ✓, `Get-LabelPolicy` ✓, `Get-AutoSensitivityLabelPolicy` ✓ |
| 02 DLP | `Get-PpaDlp` | `Get-DlpCompliancePolicy` ✓ (`.Mode`, `*Location`), `Get-DlpComplianceRule` ✓, `Get-DlpSensitiveInformationType` ✓ |
| 03 Retention | `Get-PpaRetention` | `Get-RetentionCompliancePolicy` ✓, `Get-RetentionComplianceRule` ✓, `Get-AdaptiveScope` ✓ |
| 04 Insider Risk | `Get-PpaInsiderRisk` | `Get-InsiderRiskPolicy` ⚠, `Get-InsiderRiskManagementSettings` ⚠ (E5-gated) |
| 05 Audit | `Get-PpaAudit` | `Get-AdminAuditLogConfig` ✓ (`UnifiedAuditLogIngestionEnabled`), `Get-OrganizationConfig` ✓ |
| 06 eDiscovery | `Get-PpaEdiscovery` | `Get-ComplianceCase` ✓ (`Name`, `Status`) |
| 07 Comms Compliance | `Get-PpaCommsCompliance` | `Get-SupervisoryReviewPolicyV2` ⚠ (E5-gated) |
| 08 DSPM for AI | `Get-PpaDspmAi` | `Get-DlpCompliancePolicy` filtered to the M365 Copilot location ⚠ + `DSPM for AI - *` policies |

Every collector call goes through `Invoke-PpaReadCmdlet`, which captures errors and returns a
status so a missing cmdlet / access-denied becomes a clean "not licensed" or collector-error
finding instead of a crash.

**⚠ items to verify on Microsoft Learn during Phase 3 (I will bring you the specific values):**
`Get-InsiderRiskPolicy`, `Get-InsiderRiskManagementSettings`, `Get-SupervisoryReviewPolicyV2`, the
exact Copilot service-plan id, and how the M365 Copilot DLP location is expressed.

---

## 8. Status logic (analyzers) — pointer, not restatement

The status rule for every check is in `CHECK_CATALOG.md` (LABELS-01 … AI-03). Analyzers implement
those rules exactly. The high-frequency patterns:

- **Mode = Enforce -> OK; Test / AuditAndNotify / Simulation -> Improvement** (DLP-01, LABELS-03,
  AI-02).
- **Inventory-only -> Informational** (LABELS-01, RET-01, ED-01).
- **Absent-but-worth-doing -> Recommendation** (LABELS-04, IRM-02, AI-03).
- **E5 feature on sub-E5 tenant -> Informational (not licensed)** (IRM-01, CC-01, AUD-03, ED-02).
- **Un-assertable from a session -> Verify manually** (AUD-02 only).

---

## 9. Guardrails baked into tests

- **Read-only guard** (`ReadOnlyGuard.Tests.ps1`): scans `Collect/` and `Analyze/` and **fails**
  if any `Set-/New-/Remove-/Enable-/Disable-/Update-/Add-/Start-/Stop-` verb appears, with a
  small allow-list for local file/report operations (`New-Item`, `Set-Content` on outputs).
- **No content collection:** collectors capture names, counts, modes, statuses only — never
  document/email/prompt content, file names, matched values, or keyword/regex contents.
- **Graceful degradation:** one collector's failure is recorded in that section and surfaced in
  the report; the run continues.
- **Analyzer tests:** raw fixtures -> expected statuses for the tricky rules (enforce-vs-test,
  E5-gating, simulation).
- **Render test:** sample fixture -> HTML asserts the presence of key markers (the five badge
  classes, the computed totals, each section anchor).

---

## 10. Build order (phases and check-ins)

- **Phase 1 — Sample + renderer.** Write `Samples/sample-normalized.json` (Northwind Health, the
  mock's data) and `Export-PpaHtmlReport`. **Check-in:** you compare the rendered HTML against the
  mock. We iterate here until it matches; a great report exists before any tenant call.
- **Phase 2 — Model + JSON export + tests.** `New-PpaFinding`, `ConvertTo-PpaNormalized` (compute
  counts/glance so they are no longer hand-authored in the sample), `Export-PpaJson`, and the
  render/guard tests.
- **Phase 3 — Live collectors + analyzers, one section at a time.** Verify each ⚠ cmdlet on
  Microsoft Learn first, wire the collector + analyzer into the already-working renderer, and
  **check in at each section boundary.** Start with the fully-verified sections (Labels, DLP,
  Retention, Audit, eDiscovery), then the E5-gated ones.
- **Phase 4 — Connection, entry point, README + docs.** `Connect/Disconnect`,
  `Invoke-PurviewPostureAnalyzer`, permissions/what-is-collected/interpreting docs.

---

## 11. Open items and decisions

**Settled with you:**

| # | Decision | Resolution |
|---|----------|------------|
| **D1** | Self-contained vs CDN report | **CDN links, match the mock exactly.** No inlining in v1; self-contained noted as a possible Phase 2 option only. |
| **D2** | License detection mechanism | ~~Graph `Get-MgSubscribedSku` service plans as the single source for all E5 gates + Copilot, with a fail-safe degrade when Graph is unavailable.~~ **SUPERSEDED BY D9 (2026-07-02).** |
| **D9** | **No Microsoft Graph — assume E5, annotate tier** (2026-07-02, supersedes D2; refined same day) | Graph is removed entirely: no Graph module requirement, no `Connect-MgGraph`, no consent prompts, ever. **Rationale:** the `Organization.Read.All`/`Directory.Read.All` scopes trigger admin-consent friction in client tenants — unacceptable for a drop-in consultant tool — and SKU-based detection was tenant-fragile anyway. Requirements collapse to ExchangeOnlineManagement + Compliance Reader/Global Reader. **Model (matches original CAMP): assume Microsoft 365 E5 is in place.** There is no license detection and no "License not confirmed" category. E5-gated workloads (IRM, CC, Audit Premium, eDiscovery Premium) report from **evidence exactly like E3 workloads**: data returned → real findings; genuinely empty → a normal **Improvement/Recommendation**; unreadable → Verify manually (unknown is never asserted as empty). The **`Requires: <tier>` annotation** — from the dated `Data/license-requirements.json`, sourced from the Microsoft Purview service description (verified 2026-07-02) — rides alongside those findings and **never changes or softens the verdict**; the header carries a license-context note, and the README documents the E5 assumption as the pre-requisite note (recommended: E5, or E3 + E5 Compliance). **Exception: Microsoft 365 Copilot is a separate add-on outside the E5 assumption** — DSPM for AI stays evidence-based on Copilot-location DLP artifacts (GUID `470f2276-e011-4e9d-a6ec-20768be3a4b0` / `CopilotExperiences`, readable over `Connect-IPPSSession` per the `New-DlpCompliancePolicy` reference); Copilot deployment is reported as not detectable, never asserted absent. Enforced by tests: no-Graph guard + no-license-confirmation-language guard. Supersedes the mock's "Detected licensing" banner (deliberate divergence). |

**Research items — resolved on Microsoft Learn (2026-07-01):**

| # | Item | Resolution |
|---|------|-----------|
| D3 | Device onboarding count (DLP-03) | **No clean read-only cmdlet.** DLP-03 primary signal = `EndpointDlpLocation` presence (readable); the "Devices onboarded" row degrades to **Verify manually**, never a false 0. |
| D4 | SKU-to-SIT mapping (DLP-04) | No reliable read-only per-SIT license map. Live DLP-04 reports the referenced SITs and flags named-entity detectors as **Verify manually** unless the tenant tier clearly gates them; keep the enhanced-template count as a remark. |
| D5 | Copilot service-plan id (AI-01) | Detect via Graph `Get-MgSubscribedSku` service plans named `M365_COPILOT*` (Copilot SKU GUIDs `639dec6b-bb19-468b-871c-c5c441c4b0cb` / `a809996b-059e-42e2-9866-db24b99a9782`). |
| D6 | Learn-more URLs | Kept in `Data/checks.json`; validate remaining links before shipping. |
| D7 | `Get-InsiderRiskPolicy` (new) | Not a documented cmdlet. IRM collector attempts it via the read-only wrapper and degrades; the reliable IRM signal is the Graph license gate. |
| D8 | E5 service plans (new) | Licensing is data-driven via `Data/service-plans.json` (feature -> candidate service-plan names), seeded now and finalized against the live tenant. `Get-SupervisoryReviewPolicyV2` confirmed for CC. |

---

## 12. Explicitly out of scope for v1 (Phase 2+ / later)

Offline policy-export ingestion mode; Excel output; identity redaction beyond a simple on/off; the
IRM / Communication-Compliance **AI sub-policies** within DSPM-for-AI (v1 does the DLP-for-Copilot
policy only); AI-03 "Copilot-reachable" reachability as anything more than the unlabeled-sites
signal; and any Purview area not in the mock. These are noted and set aside — no effort spent on
them now.
```
