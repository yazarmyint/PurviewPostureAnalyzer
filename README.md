# Configuration Analyzer for Microsoft Purview (CAMP v2)

A **read-only** Microsoft Purview posture analyzer. It reads your Purview configuration and
produces a single HTML report a consultant can hand to a delivery team at engagement kickoff,
plus a JSON export of the same findings.

> Not an official Microsoft product. Licensed under the MIT License (see `LICENSE` / `NOTICE`).
> Statuses are inputs to consultant judgment, not compliance determinations, and are not mapped
> to any regulatory framework.

The report covers eight workloads: **Sensitivity Labels, Data Loss Prevention, Retention & Records,
Insider Risk Management, Audit, eDiscovery, Communication Compliance,** and **DSPM for AI (Copilot).**

---

## What it does and does not do

**Does:**
- Calls read-only `Get-*` cmdlets only. It never creates, modifies, or deletes tenant configuration.
- Collects configuration **metadata** — policy/label/case names, counts, modes, scopes, and status.
- Produces `posture-report.html` (the primary deliverable) and `posture-report.json`.

**Does not:**
- Collect any content — no document/email/prompt content, file names, matched values, or
  keyword/regex contents.
- Require Global Admin, or assume you have E5, Copilot, DSPM, IRM, or Endpoint DLP. It detects and
  reports absence honestly.

A Pester test (`Tests/ReadOnlyGuard.Tests.ps1`) fails the build if any mutating cmdlet
(`Set-/New-/Remove-/Enable-/Disable-/...`) appears in the collector or analyzer code.

---

## Requirements

- **Windows PowerShell 5.1** or PowerShell 7+.
- **ExchangeOnlineManagement** module (provides `Connect-IPPSSession` and `Connect-ExchangeOnline`).
- Roles (least privilege): **Compliance Reader** (or Global Reader) for the Purview reads, plus a
  role that can read Exchange Online organization / audit config. **Global Admin is not required.**
  - Communication Compliance objects (`Get-SupervisoryReviewPolicyV2` / `Get-SupervisoryReviewRule`)
    additionally require membership in a **Communication Compliance role group** - without it those
    reads return access-denied and the report renders the CC and AI-monitoring findings as
    transparency notes instead of verdicts.
  - Insider Risk policies (`Get-InsiderRiskPolicy`) similarly require an **IRM role group** beyond
    Compliance Reader.

That's the whole list. **No Microsoft Graph** — the tool never reads licensing or directory data,
so there is no Graph module to install, no Graph scopes, and **no admin-consent prompt, ever**
(design decision D9 in `PLAN.md`).

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

### Tenant licensing (pre-requisite note, as in the original CAMP)

**Recommended: Microsoft 365 E5, or E3 + E5 Compliance (Microsoft Purview Suite).** The report
**assumes E5** when judging Purview workloads: an empty E5 workload (e.g. no Insider Risk policies)
is reported as a normal **Improvement**, exactly like any other empty workload. The tool still runs
without E5 — those findings carry a subtle **Requires: \<tier\>** annotation (from the dated
`Data/license-requirements.json`, sourced from the Microsoft Purview service description), so on a
sub-E5 tenant you read them as licensing decisions rather than configuration gaps.

The AI section follows the same rule, split by tier. **E5-included AI data security features**
(DLP for Copilot experiences, the Copilot retention location, the Communication Compliance Copilot
template, the Insider Risk *Risky AI usage* template) are judged like any other E5 workload — their
absence renders as a normal Improvement or Recommendation. **Features gated above E5** by
pay-as-you-go billing or Agent 365 licensing (DSPM collection policies, Enterprise AI apps / Other
AI apps locations, unified GenAI and third-party Communication Compliance channels) are only ever
reported as **Informational** — the report never dings a client for unpurchased SKUs. The
cmdlet-level provenance behind the AI findings (verified vs. doc-grounded vs. unverified facts) is
recorded in `docs/specs/ai-findings-build-spec.md`.

---

## How to run

```powershell
Import-Module .\PurviewPostureAnalyzer.psd1

# 1. Sign in (interactive) to the three read-only sessions.
Connect-PurviewPostureSession -UserPrincipalName consultant@contoso.com

# 2. Generate the report.
$result = Invoke-PurviewPostureAnalyzer -Organization 'Northwind Health' -OutputDirectory .\Outputs

# 3. Open the report; sign out.
Start-Process $result.HtmlPath
Disconnect-PurviewPostureSession
```

Output lands in `Outputs\PurviewPosture-<timestamp>\reports\`:
- `posture-report.html` — the report (loads Bootstrap / Font Awesome from CDNs; view online).
- `posture-report.json` — the same normalized findings, for downstream use.

If a collector can't run (module missing, not connected, or access denied), that one section
degrades to a **Verify manually** placeholder and the run continues — one failure never fails
the report.

### Run profiles: include / exclude sections

```powershell
# Only these sections:
Invoke-PurviewPostureAnalyzer -IncludeSection Sensitivity_Labels, Data_Loss_Prevention

# Everything except these:
Invoke-PurviewPostureAnalyzer -ExcludeSection DSPM_for_AI, Audit

# The same, expressed as a reusable .psd1 (or .json) profile file:
#   @{ ExcludeSection = @('DSPM_for_AI', 'Audit') }
Invoke-PurviewPostureAnalyzer -Profile .\thin-run.psd1
```

Section keys: `Sensitivity_Labels`, `Data_Loss_Prevention`, `Retention`, `Insider_Risk`,
`Audit`, `eDiscovery`, `Communication_Compliance`, `DSPM_for_AI`. Unknown keys fail fast,
before any collection. Explicit parameters override the `-Profile` file. Excluded sections
are listed in a "Sections excluded by run profile" note on the report — a thin report never
looks like a silent failure — and the posture-summary counts reflect included sections only.

### Redaction (for sharing reports outside the engagement)

```powershell
Invoke-PurviewPostureAnalyzer -Redact               # masks tenant domains, UPNs, emails
Invoke-PurviewPostureAnalyzer -Redact -RedactNames  # additionally pseudonymizes policy/label names
```

Masking is applied at **render time only** — the JSON export and in-memory findings are
untouched. Tokens are stable within a run (`user01@[redacted]`, `[redacted-domain-01]`,
`Policy-01`), so the report stays internally consistent, and a visible REDACTED banner
states the active scope. Microsoft Learn / portal URLs are never masked.

### Report features (Wave 3)

The HTML report opens with a **posture summary** (severity counts plus a linked
top-findings list), has a sticky **filter bar** (severity chips + text search), **per-finding
anchor links**, a **print stylesheet** (posture summary as page one, drill-downs expanded,
severity colors preserved — use the Print button for a client-ready PDF), and collapsible
**"How to remediate"** guidance on Improvement/Recommendation findings — portal path, a
copy-ready cmdlet where one is grounded, and a Learn link. Remediation snippets are
displayed text only, never executed, and every draft is tracked for human review in
`docs/REMEDIATION_REVIEW.md`.

To preview all of this without a tenant, run `pwsh -File tools/Build-SampleReports.ps1` —
it renders five fixture-driven sample reports (standard, dense, sparse, redacted, and
profile-filtered) plus a sample snapshot and two delta reports into the gitignored
`Samples/sample-reports/` folder and prints the paths.

### Snapshots and the delta report (Wave 4, optional)

Every report run also writes a versioned JSON **snapshot** of what the tool observed
(suppress with `-NoSnapshot`). Snapshots are **unredacted** — they contain UPNs and
scope identities; treat them as engagement-confidential (the console notice says
exactly that on every capture). The redacted HTML report remains the artifact that
travels.

The **delta report** compares two snapshots from the same client — typically the
kickoff snapshot against the engagement-close one — completely offline, with no
tenant session, on **PowerShell 7.5+ only**:

```powershell
Invoke-PurviewPostureAnalyzer -DeltaFrom .\kickoff.json -DeltaTo .\close.json
```

It leads with real change (adds, removes, renames, enforcement flips), keeps
everything the assessment could *not* see in a single "Assessment visibility"
block, and states per-section unchanged counts as the confidence signal. Full
guidance: [`docs/delta-report.md`](docs/delta-report.md).

---

## How to read the statuses

Every finding carries exactly one of five statuses:

| Status | Meaning |
|--------|---------|
| **OK** | Configured as you'd want. |
| **Improvement** | Present but weaker than it should be (e.g. a DLP policy in test mode). |
| **Recommendation** | Worth doing but a bigger conversation (licensing, HR/Legal alignment). |
| **Informational** | Inventory or context, no verdict. |
| **Verify manually** | Genuinely not assertable from a read-only session — confirm by hand. |

The report **assumes E5**: findings on E5-tier workloads get their verdict from evidence like any
other finding, with a **Requires: \<tier\>** annotation riding alongside (it never changes the
verdict). On a sub-E5 tenant, read annotated Improvements as licensing decisions first.

**Verify manually** is used sparingly and honestly — for example audit *ingestion* latency (as
opposed to merely "enabled"), per-site label coverage, the device-onboarded count, and named-entity
detector tiering. See `LIMITATIONS.md` for the full list and why each is deferred.

The card header and Solutions Summary counts are computed from these finding-level statuses; the
"Environment at a glance" strip shows each workload's headline.

---

## Known limitations

See **`LIMITATIONS.md`**. In short: a few signals cannot be read safely read-only (device
onboarding count, container/site inventory, audit ingestion, IRM policy enumeration, named-entity
SIT tiering, and the tenant's license tier itself), so they are reported as *Verify manually* or
annotated rather than guessed. Two dated maps — `Data/license-requirements.json` (which tier each
feature requires, from the Purview service description) and `Data/dlp-sit-tiers.json` (E5-gated
SITs) — must be re-verified against current Microsoft Learn periodically.

---

## Project layout

```
Public/       Connect / Disconnect / Invoke-PurviewPostureAnalyzer (the entry points)
Private/
  Collect/    read-only Get-* collectors (one per workload) + Invoke-PpaReadCmdlet wrapper
  Analyze/    analyzers (raw -> findings with statuses per CHECK_CATALOG.md)
  Model/      status model, finding/section factories, ConvertTo-PpaNormalized (assemble)
  Core/       run context, error-section helper
  Render/     Export-PpaHtmlReport (HTML) + Export-PpaJson + PpaHtml helpers
Data/         dated maps (license requirements, E5-gated SIT tiers, remediation snippets)
Samples/      sample-normalized[-dense].json fixtures + sample-raw/ per-section fixtures + rendered output
Tests/        Pester 5: read-only guard, model, render, report-polish, and per-analyzer tests
tools/        Build-SampleReports.ps1 - renders every fixture variant for browser review
docs/         specs + REMEDIATION_REVIEW.md (draft-snippet review checklist)
CHECK_CATALOG.md   the domain spec (every finding, cmdlet, and status rule)
PLAN.md            the build plan
LIMITATIONS.md     what is not assertable read-only, and why
```
