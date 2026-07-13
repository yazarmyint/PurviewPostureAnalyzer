# Purview Posture Analyzer (PPA)

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/PurviewPostureAnalyzer)](https://www.powershellgallery.com/packages/PurviewPostureAnalyzer)
[![Downloads](https://img.shields.io/powershellgallery/dt/PurviewPostureAnalyzer)](https://www.powershellgallery.com/packages/PurviewPostureAnalyzer)

A **read-only** Microsoft Purview posture analyzer. It reads your Purview configuration and
produces a single self-contained HTML report you can hand to a delivery team at engagement
kickoff, plus a JSON export of the same findings. It is a modernized successor to
[OfficeDev/CAMP](https://github.com/OfficeDev/CAMP) (see
[Licensing and attribution](#licensing-and-attribution)).

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

## Quickstart

Requires PowerShell 5.1+ (or 7+) and the ExchangeOnlineManagement module — see
[Requirements](#requirements).

```powershell
Install-Module PurviewPostureAnalyzer -Scope CurrentUser
Import-Module PurviewPostureAnalyzer

# One command: sign in, run, open the report, sign out.
Invoke-PurviewPostureAnalyzer -Organization 'Northwind Health' -OutputDirectory .\Outputs -Connect -Show -Disconnect
```

`-Connect` opens the two read-only sessions interactively (add `-UserPrincipalName
you@contoso.com` to pre-fill the account); it never disturbs sessions already live. `-Show`
opens the finished report; `-Disconnect` signs you out afterward — even if the run fails.
Output lands in `Outputs\PurviewPosture-<timestamp>\reports\` as `posture-report.html`
(self-contained, opens offline) and `posture-report.json`.

Need to brand the report, assess a client tenant as a guest, run only some sections, or
redact for sharing? See [Usage](#usage).

### The "untrusted repository" prompt

Your first Gallery install prompts you to confirm, because PowerShell marks the PowerShell
Gallery as untrusted by default. This is normal and applies to **every** Gallery module, not
just this one — enter **Y** to proceed. To skip it on future installs, mark the Gallery
trusted for your machine (this trusts the **entire** Gallery, so it's your call):

```powershell
Set-PSResourceRepository -Name PSGallery -Trusted                # PowerShell 7 (PSResourceGet)
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted     # Windows PowerShell 5.1
```

---

## What it does and does not do

**Does:**
- Calls read-only `Get-*` cmdlets only, over two interactive sessions: Security & Compliance
  PowerShell (`Connect-IPPSSession`) and Exchange Online (`Connect-ExchangeOnline`).
- Collects configuration **metadata** — policy / label / case names, counts, modes, scopes,
  and status.
- Produces `posture-report.html` (the primary deliverable) and `posture-report.json`.

**Does not:**
- Collect any content — no document / email / prompt content, file names, matched values, or
  keyword / regex contents.
- Require Global Admin, or assume you have E5, Copilot, DSPM, IRM, or Endpoint DLP — it
  detects and reports absence honestly.
- Touch Microsoft Graph — no Graph module, no Graph scopes, and **no admin-consent prompt,
  ever** (design decision D9 in `PLAN.md`).

---

## What's in scope

PPA reports on **eight Purview workloads** (28 checks). Each check has a stable ID;
**[`CHECK_CATALOG.md`](CHECK_CATALOG.md) is the authoritative spec** — every check, the
cmdlet and property it reads, and the status rule.

| Workload | What it covers | Checks |
|----------|----------------|:------:|
| **Sensitivity Labels** | Label taxonomy, publishing, auto-labeling, container labels, Azure RMS | 5 |
| **Data Loss Prevention** | Policy enforcement mode, Teams coverage, Endpoint DLP | 3 |
| **Retention & Records** | Retention policies and labels, adaptive scopes, auto-apply | 3 |
| **Insider Risk Management** *(E5)* | Policies, licensing posture, key templates (risky AI usage, departing-employee theft, data-leak family) | 5 |
| **Audit** | Unified audit logging, Audit Premium, mailbox-auditing defaults | 3 |
| **eDiscovery** | Cases in use, eDiscovery Premium | 2 |
| **Communication Compliance** *(E5)* | Policy presence | 1 |
| **DSPM for AI (Copilot)** | AI surface, Copilot DLP, label-based exclusion, DSPM collection policies, AI-app retention, Comms Compliance monitoring | 6 |

**DSPM for AI** is the newest section and spans DLP, retention, and Communication Compliance
evidence. E5-included AI features are judged like any other E5 workload; features gated
*above* E5 (pay-as-you-go / Agent 365) are only ever reported as Informational — the report
never dings you for unpurchased SKUs.

Every finding carries exactly one of five statuses:

| Status | Meaning |
|--------|---------|
| **OK** | Configured as you'd want. |
| **Improvement** | Present but weaker than it should be (e.g. a DLP policy in test mode). |
| **Recommendation** | Worth doing but a bigger conversation (licensing, HR / Legal alignment). |
| **Informational** | Inventory or context, no verdict. |
| **Verify manually** | Genuinely not assertable from a read-only session — confirm by hand. |

`Verify manually` is used sparingly and honestly (e.g. audit *ingestion* latency vs. merely
"enabled", per-site label coverage, the device-onboarded count). See
[`LIMITATIONS.md`](LIMITATIONS.md) for the full list and why each is deferred.

---

## What the report looks like

The HTML report is **self-contained** — inline CSS and data-URI SVG icons, no external
stylesheets, scripts, fonts, or CDN calls — so it renders fully offline. The Solutions
Summary and every finding's title and status read without scripting; enable scripting to
expand a finding's full drill-down on screen, or print the report, which forces every section
open.

It opens with a **posture summary** (severity counts plus a linked top-findings list) and an
**Environment at a glance** strip, and includes:

- a sticky **filter bar** (severity chips + text search) and **per-finding anchor links**;
- a **coverage matrix** showing which workloads the run could and could not read;
- a **print stylesheet** (posture summary as page one, drill-downs expanded, colors
  preserved) — use the browser Print button for a client-ready PDF;
- collapsible **"How to remediate"** guidance on Improvement / Recommendation findings —
  portal-first prose and a Learn link only (**no PowerShell snippets**; a one-line cmdlet
  misrepresents what remediation involves). Guidance is displayed text, never executed;
  confirm against the current Microsoft Learn article before acting. Sourcing rationale:
  [`docs/REMEDIATION_REVIEW.md`](docs/REMEDIATION_REVIEW.md).

Preview all of this **without a tenant** by rendering the fixture-driven samples:

```powershell
pwsh -File tools/Build-SampleReports.ps1
```

It writes standard, dense, sparse, redacted, and profile-filtered sample reports (plus a
snapshot and two delta reports) into the gitignored `Samples/sample-reports/` folder and
prints the paths.

### Snapshots, the run manifest, and the delta report

Every run writes a versioned JSON **snapshot** of what the tool observed (suppress with
`-NoSnapshot`). Snapshots are **unredacted** — they contain UPNs and scope identities; treat
them as engagement-confidential (the console says so on every capture). The redacted HTML
report remains the artifact that travels.

Every run also writes a **run manifest** (`posture-run-manifest.json`) next to the report —
the tool's self-audit trail. For each read dispatched through the read-only wrapper it records
the cmdlet, result status, object count, and UTC timestamp, under a metadata header (tool,
schema/PPA version, PowerShell edition, run start/end). It is **metadata only** — never
arguments, filter strings, policy content, or tenant identifiers — and it records the `Get-*`
reads but **not** the `Connect-*` sign-ins (which don't pass through the wrapper), so a SOC
should read it as a record of *reads*, not connection events. It stays with the report under
`Outputs/` and never leaves the machine.

The **delta report** compares two snapshots from the same tenant — typically kickoff against
engagement-close — completely offline, with no session, on **PowerShell 7.5+ only**:

```powershell
Invoke-PurviewPostureAnalyzer -DeltaFrom .\kickoff.json -DeltaTo .\close.json
```

It leads with real change (adds, removes, renames, enforcement flips), gathers everything the
assessment could *not* see into one "Assessment visibility" block, and states per-section
unchanged counts as the confidence signal. Full guidance:
[`docs/delta-report.md`](docs/delta-report.md).

---

## Requirements

- **Windows PowerShell 5.1** or **PowerShell 7+** (7.5+ for the optional delta report).
- The **ExchangeOnlineManagement** module — PPA **requires** it to connect to Microsoft
  Purview (it provides `Connect-IPPSSession` and `Connect-ExchangeOnline`). Without it, PPA
  stops before connecting. Install it with:

```powershell
  Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

- Read permissions in the tenant (see [Roles and permissions](#roles-and-permissions)).
  **Global Admin is not required.**

### Tenant licensing

**Recommended: Microsoft 365 E5, or E3 + E5 Compliance (Microsoft Purview Suite).** The report
**assumes E5** when judging Purview workloads: an empty E5 workload (e.g. no Insider Risk
policies) is reported as a normal **Improvement**, exactly like any other empty workload. The
tool still runs without E5 — those findings carry a subtle **Requires: \<tier\>** annotation
(from the dated `Data/license-requirements.json`, sourced from the Microsoft Purview service
description), so on a sub-E5 tenant you read them as licensing decisions rather than
configuration gaps. The annotation never changes a verdict.

---

## Roles and permissions

PPA degrades **per section**: if a read is denied, that section renders as a transparency /
*Verify manually* note and the run continues. A lower-privilege account still produces a
usable report — the sections it can't read simply show less, and one failure never fails the
report.

| Check family | Session | Global Reader | Compliance Admin / Data Admin | Also needs a specialist role group |
|--------------|---------|:-------------:|:-----------------------------:|------------------------------------|
| Sensitivity Labels | S&C | Yes | Yes | — |
| Azure Rights Management (`LABELS-05`) | Exchange Online | Yes | Yes | — |
| Data Loss Prevention | S&C | Yes | Yes | — |
| Retention & Records | S&C | Yes | Yes | — |
| Audit | Exchange Online | Yes | Yes | — |
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

## Usage

All examples assume the module is imported (`Import-Module PurviewPostureAnalyzer`). The
[Quickstart](#quickstart) one-liner covers the common case; the sections below are for when
you need more control.

### Keep the session under your own control

Running several tools against the same tenant in one sitting? Use the four-step flow — PPA
leaves the session alone:

```powershell
# 1. Sign in (interactive) to the two read-only sessions.
Connect-PurviewPostureSession -UserPrincipalName you@contoso.com

# 2. Generate the report (the session survives this — and any other tool you run).
$result = Invoke-PurviewPostureAnalyzer -Organization 'Northwind Health' -OutputDirectory .\Outputs

# 3. Open the report.
Start-Process $result.HtmlPath

# 4. Sign out when YOU are done.
Disconnect-PurviewPostureSession
```

> **You own session teardown — by default.** PPA closes sessions **only** when you pass
> `-Disconnect` (and then even on a failed run). Without `-Disconnect`, nothing is torn down:
> if the run throws part-way through, the authenticated sessions stay open — run
> `Disconnect-PurviewPostureSession` yourself before you leave the console.

### Assess a client tenant as a B2B guest

Invited as a guest into a customer's tenant? Pass `-DelegatedOrganization` with the client's
tenant domain and PPA connects both read-only sessions to **their** tenant:

```powershell
# Sign in to the CLIENT tenant as a guest, then run as usual.
Connect-PurviewPostureSession -UserPrincipalName you@yourfirm.com -DelegatedOrganization client.onmicrosoft.com
Invoke-PurviewPostureAnalyzer -Organization 'Client' -OutputDirectory .\Outputs

# Or the one-liner:
Invoke-PurviewPostureAnalyzer -Organization 'Client' -OutputDirectory .\Outputs -Connect -DelegatedOrganization client.onmicrosoft.com -Show -Disconnect
```

- `-AzureADAuthorizationEndpointUri` is optional — auto-derived from the client domain
  (`https://login.microsoftonline.com/<domain>`); pass it only to override. (It applies to
  the S&C session; Exchange Online needs only the delegated organization.)
- Your guest account must hold **Compliance Administrator** (or an equivalent read-capable
  role) *in the client tenant*.
- Requires ExchangeOnlineManagement **3.0.0+**. Commercial cloud only.

### Run only some sections

```powershell
# Only these sections:
Invoke-PurviewPostureAnalyzer -IncludeSection Sensitivity_Labels, Data_Loss_Prevention

# Everything except these:
Invoke-PurviewPostureAnalyzer -ExcludeSection DSPM_for_AI, Audit

# The same, as a reusable .psd1 (or .json) profile file — @{ ExcludeSection = @('DSPM_for_AI', 'Audit') }:
Invoke-PurviewPostureAnalyzer -Profile .\thin-run.psd1
```

Section keys: `Sensitivity_Labels`, `Data_Loss_Prevention`, `Retention`, `Insider_Risk`,
`Audit`, `eDiscovery`, `Communication_Compliance`, `DSPM_for_AI`. Unknown keys fail fast,
before any collection. Explicit parameters override the `-Profile` file. Excluded sections are
listed in a note on the report — a thin report never looks like a silent failure — and
posture-summary counts reflect included sections only.

### Redact for sharing outside the engagement

```powershell
Invoke-PurviewPostureAnalyzer -Redact               # masks tenant domains, UPNs, emails
Invoke-PurviewPostureAnalyzer -Redact -RedactNames  # additionally pseudonymizes policy / label names
```

Masking is applied at **render time only** — the JSON export and in-memory findings are
untouched. Tokens are stable within a run (`user01@[redacted]`, `[redacted-domain-01]`,
`Policy-01`), so the report stays internally consistent, and a visible REDACTED banner states
the active scope. Microsoft Learn / portal URLs are never masked.

### Custom logo

Embed a client logo in the report header with `-LogoPath`:

```powershell
Invoke-PurviewPostureAnalyzer -Organization 'Northwind Health' -LogoPath .\client-logo.png
```

- **Allowed types:** `.png`, `.jpg`, `.jpeg` — anything else (or a missing file) fails the
  run up front.
- Embedded as a **data: URI**, so the report stays self-contained and offline.
- Report chrome only — never enters the JSON export or snapshots.
- Files over **500 KB** trigger a size warning (the image is embedded into every report it
  brands, so keep it small).
- Delta mode (`-DeltaFrom`/`-DeltaTo`) ignores `-LogoPath` with a warning; without
  `-LogoPath` the header slot renders nothing.

`Image/logo.jpg` is the sample fixture — the sample build embeds it into `sample-standard.html`
so the feature is visible in the shipped samples.

---

## Licensing and attribution

Licensed under the **MIT License** (see `LICENSE`). PPA is an independent, community-maintained
project — **not** a Microsoft product and not endorsed by or affiliated with Microsoft (see
`NOTICE`).

It is **derived in part from** the MIT-licensed
[Configuration Analyzer for Microsoft Purview (CAMP)](https://github.com/OfficeDev/CAMP),
Copyright (c) Microsoft Corporation — the original license and copyright are preserved in
`LICENSE` and attributed in `NOTICE`. The collection, analysis, and reporting logic has been
rewritten; the original CAMP engine is kept for provenance under `archive/legacy/` (superseded
— do not run).

**Open-source components:** none bundled at runtime. The HTML report is self-contained —
hand-written inline CSS and data-URI SVG icons, no third-party CSS/JS frameworks, fonts, or CDN
dependencies.

---

## Contributing, security, and support

Contributions are welcome by pull request. See **`CONTRIBUTING.md`** for the dev conventions:
ASCII-only PowerShell 5.1 source, the read-only and no-Graph guards, the five-status model and
`CHECK_CATALOG.md` as the domain spec, Pester 5 with pinned assertions, and the branch +
both-engine-gate workflow.

For a suspected security vulnerability **in the tool**, use private reporting — see
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
tools/        Build-SampleReports.ps1, New-DeltaFixturePair.ps1, Build-PublishPackage.ps1, Test-PublishPackage.ps1
docs/         delta-report guide, REMEDIATION_REVIEW, KEY_SOURCES, specs/
archive/      legacy/ - the original OfficeDev/CAMP engine, retained for provenance (do not run)
CHECK_CATALOG.md   the domain spec (every finding, cmdlet, and status rule)
PLAN.md            the build plan
LIMITATIONS.md     what is not assertable read-only, and why
```
