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
Data/         dated maps (license requirements per check, E5-gated SIT tiers)
Samples/      sample-normalized.json fixture + sample-raw/ per-section fixtures + rendered output
Tests/        Pester 5: read-only guard, model, render, and per-analyzer tests
CHECK_CATALOG.md   the domain spec (every finding, cmdlet, and status rule)
PLAN.md            the build plan
LIMITATIONS.md     what is not assertable read-only, and why
```
