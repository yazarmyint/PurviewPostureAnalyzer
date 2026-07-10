# Purview Posture Analyzer (PPA)

A **read-only** Microsoft Purview posture analyzer. It reads your Purview configuration and
produces a single self-contained HTML report you can hand to a delivery team at engagement
kickoff, plus a JSON export of the same findings. It is a modernized successor to
[OfficeDev/CAMP](https://github.com/OfficeDev/CAMP) (see [Attribution](#licensing-and-attribution)).

**See a live sample report** (Acme Corporation, demonstration data):
<https://yazarmyint.github.io/PurviewPostureAnalyzer/>

> **Read-only, always.** PPA only calls read `Get-*` cmdlets (and `Connect-*` to open
> sessions). It never creates, modifies, or deletes any tenant configuration, and it
> collects no content. A Pester guard (`Tests/ReadOnlyGuard.Tests.ps1`) fails the build if
> a mutating cmdlet (`Set-/New-/Remove-/Enable-/Disable-/...`) ever appears in the
> collector, analyzer, or entry-point code.

> Not an official Microsoft product (see `NOTICE`). Licensed under the MIT License. Statuses
> are inputs to *your* judgment, not compliance determinations, and are not mapped to any
> regulatory framework.

---

## What it does and does not do

**Does:**
- Calls read-only `Get-*` cmdlets only, over two interactive sessions:
  Security & Compliance PowerShell (`Connect-IPPSSession`) and Exchange Online
  (`Connect-ExchangeOnline`).
- Collects configuration **metadata** - policy / label / case names, counts, modes, scopes,
  and status.
- Produces `posture-report.html` (the primary deliverable) and `posture-report.json`.

**Does not:**
- Collect any content - no document / email / prompt content, file names, matched values, or
  keyword / regex contents.
- Require Global Admin, or assume you have E5, Copilot, DSPM, IRM, or Endpoint DLP. It detects
  and reports absence honestly.
- Touch Microsoft Graph. The tool reads no licensing or directory data, so there is no Graph
  module to install, no Graph scopes, and **no admin-consent prompt, ever** (design decision
  D9 in `PLAN.md`).

---

## What's in scope

PPA reports on **eight Purview workloads**. Each check has a stable ID; `CHECK_CATALOG.md` is
the authoritative spec (every check, the cmdlet and property it reads, and the status rule).

| Workload | Checks |
|----------|--------|
| **Sensitivity Labels** | `LABELS-01` taxonomy · `LABELS-02` publishing · `LABELS-03` auto-labeling mode · `LABELS-04` container labels · `LABELS-05` Azure Rights Management |
| **Data Loss Prevention** | `DLP-01` enforce vs. test · `DLP-02` Teams coverage · `DLP-03` Endpoint DLP |
| **Retention & Records** | `RET-01` policies & labels · `RET-02` adaptive scopes · `RET-03` auto-apply |
| **Insider Risk Management** *(E5)* | `IRM-01` policies · `IRM-02` licensing recommendation · `IRM-03` risky-AI-usage template · `IRM-04` departing-employee theft · `IRM-05` data-leak family |
| **Audit** | `AUD-01` unified audit logging · `AUD-03` Audit Premium · `AUD-04` mailbox-auditing default |
| **eDiscovery** | `ED-01` cases in use · `ED-02` eDiscovery Premium |
| **Communication Compliance** *(E5)* | `CC-01` policies |
| **DSPM for AI (Copilot)** | `AI-01` AI surface · `AI-02` Copilot DLP · `AI-03` label-based exclusion · `AI-04` DSPM collection policies · `AI-05` AI-app retention · `AI-06` Communication Compliance Copilot monitoring |

The **DSPM for AI** section is called out because it is the newest and spans DLP, retention,
and Communication Compliance evidence. E5-included AI features are judged like any other E5
workload; features gated *above* E5 (pay-as-you-go / Agent 365) are only ever reported as
Informational - the report never dings you for unpurchased SKUs.

Every finding carries exactly one of five statuses:

| Status | Meaning |
|--------|---------|
| **OK** | Configured as you'd want. |
| **Improvement** | Present but weaker than it should be (e.g. a DLP policy in test mode). |
| **Recommendation** | Worth doing but a bigger conversation (licensing, HR / Legal alignment). |
| **Informational** | Inventory or context, no verdict. |
| **Verify manually** | Genuinely not assertable from a read-only session - confirm by hand. |

`Verify manually` is used sparingly and honestly (e.g. audit *ingestion* latency as opposed to
merely "enabled", per-site label coverage, the device-onboarded count). See `LIMITATIONS.md`
for the full list and why each is deferred.

---

## What the report looks like

The HTML report is **self-contained**: inline CSS and data-URI SVG icons, with no external
stylesheets, scripts, fonts, or CDN calls, so it renders fully offline. The Solutions Summary
and every finding's title and status read without scripting; to expand a finding's full
drill-down detail (and the collapsible summary bodies) on screen, enable scripting - or print
the report, which forces every section open. It opens with a **posture summary** (severity
counts plus a linked top-findings list) and an **Environment at a glance** strip, and includes:

- a sticky **filter bar** (severity chips + text search) and **per-finding anchor links**;
- a **coverage matrix** showing which workloads the run could and could not read;
- a **print stylesheet** (posture summary as page one, drill-downs expanded, severity colors
  preserved) - use the browser Print button for a client-ready PDF;
- collapsible **"How to remediate"** guidance on Improvement / Recommendation findings -
  portal-first prose and a Learn link only (**no PowerShell snippets**; a one-line cmdlet
  misrepresents what remediation involves). Guidance is displayed text, never executed;
  Microsoft guidance evolves, so confirm against the current Microsoft Learn article before
  acting. The sourcing rationale is recorded in `docs/REMEDIATION_REVIEW.md`.

To preview all of this **without a tenant**, render the fixture-driven samples:

```powershell
pwsh -File tools/Build-SampleReports.ps1
```

It writes standard, dense, sparse, redacted, and profile-filtered sample reports (plus a
sample snapshot and two delta reports) into the gitignored `Samples/sample-reports/` folder
and prints the paths.

### Snapshots and the delta report

Every run also writes a versioned JSON **snapshot** of what the tool observed (suppress with
`-NoSnapshot`). Snapshots are **unredacted** - they contain UPNs and scope identities; treat
them as engagement-confidential (the console says so on every capture). The redacted HTML
report remains the artifact that travels.

Every run also writes a **run manifest** (`posture-run-manifest.json`) next to the report - the
tool's self-audit trail. For **each read dispatched through the read-only wrapper** it records
the cmdlet name, result status, object count and a UTC timestamp, under a header (tool, schema
version, PPA version, PowerShell edition + version, run start/end). It is **metadata only** -
never arguments, filter strings, policy content or tenant identifiers - so there is nothing to
redact. **Scope:** it lists the `Get-*` reads the wrapper ran; it does **not** record the
`Connect-IPPSSession` / `Connect-ExchangeOnline` sign-ins, which don't pass through the wrapper -
so a SOC correlating against sign-in logs should read it as a record of *reads*, not of
connection or sign-in events. It is written to the same folder as the report - under `Outputs/`
(git-ignored) on a default run, or wherever you point `-OutputDirectory` (yours to protect, same
as snapshots) - and never leaves the machine. Emitted on every run (best-effort: written after
collection and before the report render, so a hard crash before that point yields none).

The **delta report** compares two snapshots from the same tenant - typically the kickoff
snapshot against the engagement-close one - completely offline, with no session, on
**PowerShell 7.5+ only**:

```powershell
Invoke-PurviewPostureAnalyzer -DeltaFrom .\kickoff.json -DeltaTo .\close.json
```

It leads with real change (adds, removes, renames, enforcement flips), gathers everything the
assessment could *not* see into one "Assessment visibility" block, and states per-section
unchanged counts as the confidence signal. Full guidance: [`docs/delta-report.md`](docs/delta-report.md).

---

## Requirements

- **Windows PowerShell 5.1** or **PowerShell 7+** (7.5+ for the optional delta report).
- The **ExchangeOnlineManagement** module (provides `Connect-IPPSSession` and
  `Connect-ExchangeOnline`):

  ```powershell
  Install-Module ExchangeOnlineManagement -Scope CurrentUser
  ```

- Read permissions in the tenant (see [Roles and permissions](#roles-and-permissions) below).
  **Global Admin is not required.**

### Tenant licensing

**Recommended: Microsoft 365 E5, or E3 + E5 Compliance (Microsoft Purview Suite).** The report
**assumes E5** when judging Purview workloads: an empty E5 workload (e.g. no Insider Risk
policies) is reported as a normal **Improvement**, exactly like any other empty workload. The
tool still runs without E5 - those findings carry a subtle **Requires: \<tier\>** annotation
(from the dated `Data/license-requirements.json`, sourced from the Microsoft Purview service
description), so on a sub-E5 tenant you read them as licensing decisions rather than
configuration gaps. The annotation never changes a verdict. The cmdlet-level provenance behind
the AI findings is recorded in `docs/specs/ai-findings-build-spec.md`.

---

## Roles and permissions

PPA degrades **per section**: if a read is denied, that section renders as a transparency /
*Verify manually* note and the run continues. So a lower-privilege account still produces a
usable report - the sections it can't read simply show less, and one failure never fails the
report.

| Check family | Session | Global Reader | Compliance Admin / Data Admin | Also needs a specialist role group |
|--------------|---------|:-------------:|:-----------------------------:|------------------------------------|
| Sensitivity Labels | S&C | Yes | Yes | - |
| Azure Rights Management (`LABELS-05`) | Exchange Online | Yes | Yes | - |
| Data Loss Prevention | S&C | Yes | Yes | - |
| Retention & Records | S&C | Yes | Yes | - |
| Audit | Exchange Online | Yes | Yes | - |
| eDiscovery | S&C | No | Yes | eDiscovery Manager / Administrator |
| Insider Risk Management | S&C | No | No | Insider Risk Management |
| Communication Compliance | S&C | No | No | Communication Compliance |
| DSPM for AI (Copilot) | S&C | Partial | Partial | Communication Compliance (for the `AI-06` monitoring sub-read) |

*S&C = Security & Compliance PowerShell (`Connect-IPPSSession`). Exact role names and the
permissions each grants can vary with tenant RBAC; confirm against current Microsoft Learn.*

**Least privilege:** **Global Reader** alone covers Sensitivity Labels, DLP, Retention, Audit,
and Azure Rights Management. For full coverage, add the **Insider Risk Management** and
**Communication Compliance** role groups and an **eDiscovery** role. **Global Admin is never
required.**

---

## Quickstart

The module is not published to the PowerShell Gallery yet - **clone and run** it locally.

```powershell
git clone https://github.com/yazarmyint/PurviewPostureAnalyzer.git
cd PurviewPostureAnalyzer
Import-Module .\PurviewPostureAnalyzer.psd1

# One command: sign in, run, open the report, sign out.
Invoke-PurviewPostureAnalyzer -Organization 'Northwind Health' -OutputDirectory .\Outputs -Connect -Show -Disconnect
```

`-Connect` prompts you interactively for the two read-only sessions
(`-UserPrincipalName you@contoso.com` is optional and pre-fills the account); it never
disturbs sessions that are already live. `-Show` opens the finished report in your browser;
`-Disconnect` signs you out afterwards - even when the run fails. Want the report branded?
Add `-LogoPath .\client-logo.png` (see [Custom logo](#custom-logo)).

Running several tools against the same tenant in one sitting? Keep the session under your
own control with the four-step flow - PPA leaves it alone:

```powershell
# 1. Sign in (interactive) to the two read-only sessions.
Connect-PurviewPostureSession -UserPrincipalName you@contoso.com

# 2. Generate the report (the session survives this - and any other tool you run).
$result = Invoke-PurviewPostureAnalyzer -Organization 'Northwind Health' -OutputDirectory .\Outputs

# 3. Open the report.
Start-Process $result.HtmlPath

# 4. Sign out when YOU are done with the session.
Disconnect-PurviewPostureSession
```

Output lands in `Outputs\PurviewPosture-<timestamp>\reports\`:
- `posture-report.html` - the report (self-contained; opens in any browser, offline).
- `posture-report.json` - the same normalized findings, for downstream use.

> **You own session teardown - by default.** PPA closes sessions **only** when you pass
> `-Disconnect`, and then it disconnects even on a failed run. Without `-Disconnect` nothing
> is ever torn down: if the run throws part-way through, the authenticated Security &
> Compliance and Exchange Online sessions stay open - run `Disconnect-PurviewPostureSession`
> yourself before you leave the console.

### Run profiles: include / exclude sections

```powershell
# Only these sections:
Invoke-PurviewPostureAnalyzer -IncludeSection Sensitivity_Labels, Data_Loss_Prevention

# Everything except these:
Invoke-PurviewPostureAnalyzer -ExcludeSection DSPM_for_AI, Audit

# The same, as a reusable .psd1 (or .json) profile file:
#   @{ ExcludeSection = @('DSPM_for_AI', 'Audit') }
Invoke-PurviewPostureAnalyzer -Profile .\thin-run.psd1
```

Section keys: `Sensitivity_Labels`, `Data_Loss_Prevention`, `Retention`, `Insider_Risk`,
`Audit`, `eDiscovery`, `Communication_Compliance`, `DSPM_for_AI`. Unknown keys fail fast,
before any collection. Explicit parameters override the `-Profile` file. Excluded sections are
listed in a "Sections excluded by run profile" note on the report - a thin report never looks
like a silent failure - and the posture-summary counts reflect included sections only.

### Redaction (for sharing reports outside the engagement)

```powershell
Invoke-PurviewPostureAnalyzer -Redact               # masks tenant domains, UPNs, emails
Invoke-PurviewPostureAnalyzer -Redact -RedactNames  # additionally pseudonymizes policy / label names
```

Masking is applied at **render time only** - the JSON export and in-memory findings are
untouched. Tokens are stable within a run (`user01@[redacted]`, `[redacted-domain-01]`,
`Policy-01`), so the report stays internally consistent, and a visible REDACTED banner states
the active scope. Microsoft Learn / portal URLs are never masked.

---

## Licensing and attribution

Licensed under the **MIT License** (see `LICENSE`). PPA is an independent,
community-maintained project - **not** a Microsoft product and not endorsed by or affiliated
with Microsoft (see `NOTICE`).

It is **derived in part from** the MIT-licensed
[Configuration Analyzer for Microsoft Purview (CAMP)](https://github.com/OfficeDev/CAMP),
Copyright (c) Microsoft Corporation - the original license and copyright are preserved in
`LICENSE` and attributed in `NOTICE`. The collection, analysis, and reporting logic has been
rewritten; the original CAMP engine is kept for provenance under `archive/legacy/` (superseded
- do not run).

**Open-source components:** none bundled at runtime. The HTML report is self-contained -
hand-written inline CSS and data-URI SVG icons, no third-party CSS/JS frameworks, fonts, or CDN
dependencies.

---

## Custom logo

Embed a client logo in the report header with `-LogoPath`:

```powershell
Invoke-PurviewPostureAnalyzer -Organization 'Northwind Health' -LogoPath .\client-logo.png
```

- **Allowed types:** `.png`, `.jpg`, `.jpeg` - anything else (or a missing file) fails the run
  up front, before any collection.
- The image is embedded into the HTML as a **data: URI**, so the report stays fully
  self-contained and offline - no external asset reference is added.
- The logo is report chrome only: it never enters the JSON export or snapshots.
- Files over **500 KB** trigger a size warning - the image is embedded into every report it
  brands, so keep it small.
- Delta mode (`-DeltaFrom`/`-DeltaTo`) ignores `-LogoPath` with a warning.
- Without `-LogoPath` the header slot renders nothing (no placeholder).

`Image/logo.jpg` is the sample fixture: the sample-report build embeds it into
`sample-standard.html` so the feature is visible in the shipped samples.

---

## Contributing

Contributions are welcome by pull request. See **`CONTRIBUTING.md`** for the dev conventions:
ASCII-only PowerShell 5.1 source, the read-only and no-Graph guards, the five-status model and
`CHECK_CATALOG.md` as the domain spec, Pester 5 with pinned assertions, and the branch +
both-engine-gate workflow.

For a suspected security vulnerability **in the tool**, use private reporting - see
`SECURITY.md`. For bugs and questions, see `SUPPORT.md`.

---

## Repository layout

```
Public/       Connect / Disconnect / Invoke-PurviewPostureAnalyzer (the entry points)
Private/
  Collect/    read-only Get-* collectors (one per workload) + Invoke-PpaReadCmdlet wrapper
  Analyze/    analyzers (raw -> findings with statuses per CHECK_CATALOG.md) + coverage model
  Model/      status model, finding / section / snapshot factories, ConvertTo-PpaNormalized
  Core/       run context, section select, delta, error-section helper, data-map loaders
  Render/     Export-PpaHtmlReport (HTML) + Export-PpaJson + Export-PpaDeltaReport + helpers
Data/         dated maps: license requirements + remediation guidance
Samples/      sample-normalized[-dense].json + sample-raw/ + delta-fixtures/ (test fixtures)
Tests/        Pester 5: read-only guard, model, render, coverage, snapshot, delta, per-analyzer
tools/        Build-SampleReports.ps1, New-DeltaFixturePair.ps1
docs/         delta-report guide, REMEDIATION_REVIEW, KEY_SOURCES, specs/
archive/      legacy/ - the original OfficeDev/CAMP engine, retained for provenance (do not run)
CHECK_CATALOG.md   the domain spec (every finding, cmdlet, and status rule)
PLAN.md            the build plan
LIMITATIONS.md     what is not assertable read-only, and why
```
