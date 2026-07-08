# PurviewPostureAnalyzer — Repo Hygiene & README: Inventory & Analysis

> **Read-only report.** This document changes nothing in the repo. It is written to repo root
> for human triage and is intentionally **not** `git add`-ed or committed. Every disposition
> below is a *recommendation only* — do not act on it without human review.
>
> Generated: 2026-07-07 · Branch `feature/report-a-v2-design` @ `658c799` · Reference tool: OfficeDev/CAMP (shallow clone in scratchpad, outside this repo).

---

## 0. Working state

| Question | Finding |
|---|---|
| Current branch | `feature/report-a-v2-design` |
| Tip commit | `658c799` — *Wave 6 reincorporation Part 3: IRM-04 departing-employee theft + IRM-05 data leaks* |
| Is Wave 6 the tip? | **Yes.** The three tip commits are Wave 6: `c3d10ca` (AUD-04 + AUD-02 rider), `b2471d7` (LABELS-05 Azure RMS), `658c799` (IRM-04 + IRM-05). All four target checks (AUD-04, LABELS-05, IRM-04, IRM-05) are present in `CHECK_CATALOG.md`. |
| Branch pushed to origin? | **Partially.** Local `feature/report-a-v2-design` is **ahead 3** of `origin/feature/report-a-v2-design`, which still sits at `fb98cb4` (the pre-Wave-6 wording sweep). The three Wave 6 commits **do** exist on origin, but under separate branches: `origin/wave6-reincorp-part1` = `c3d10ca`, `part2` = `b2471d7`, `part3` = `658c799`. So the work is pushed; the **integration branch on origin has not been fast-forwarded** to include it. (Consistent with the memory note "unpushed merge".) |
| Promoted to `main`? | **No.** Local `main` = origin `main` = `4039855` *"Initial commit"*. **No feature work of any wave has been merged to `main`.** The entire tool lives only on feature branches. |
| Working tree clean? | **No modified tracked files.** Untracked only: the folder `Samples/design-explorations/` (14 files) and `docs/port-to-generator-brief.md`, `docs/ux-polish-brief.md`, `docs/ux-redesign-brief.md`. Ignored-but-present-on-disk: `.claude/settings.local.json` and 24 files under `Samples/sample-reports/`. |

**Note for the publish session:** because nothing is on `main`, a future "publish from `main`" step has nothing to publish yet — promotion of `feature/report-a-v2-design` (or a release branch) to `main` is a prerequisite.

---

## 1. CAMP reference notes (OfficeDev/CAMP README)

**Section order (headings, in order):**

1. `# Overview`
2. `# What is Configuration Analyzer for Microsoft Purview (CAMP)?`
3. `# Why should I use it?`
4. `# What is in scope?` — enumerates 8 solutions across 4 families (MIP: DLP, IP; MIG: IG, RM; Insider Risk: CC, IRM; Discovery & Response: Audit, eDiscovery)
5. `# That is awesome! How do I run it?` → `# Pre-Requisites` (subscription/add-on; PS 5.1+; ExchangeOnlineManagement; **roles/permissions matrix**)
6. `# Install Guide` (`Install-Module -Name CAMP`; `Get-CAMPReport`; Input Parameters: Geo, Solution, ExchangeEnvironmentName, TurnOffDataCollection)
7. `# License` (open-source components: Bootstrap, Font Awesome, clipboard.js)
8. `## Frequently Asked Questions (FAQ)` — read-only reassurance; report sections; **status-vocabulary definitions**; logo replacement; saving/printing
9. `# Contributing`
10. `# Trademark`

**Standout structural elements worth borrowing (structure, not content):**

- **Reader-question headers** ("Why should I use it?", "What is in scope?", "That is awesome! How do I run it?", "How do I save my report?") — approachable, scannable.
- **Explicit "What is in scope?" section** up front, listing every solution the tool covers.
- **Prerequisites bundled *before* install** — subscription reality, PowerShell version, module, and permissions all in one place.
- **Roles/permissions matrix** — `User Role × {DLP, IP, IG, RM, IRM, CC, Audit, eDiscovery}` with Yes/No cells and superscript footnoted exceptions. This is the single most reusable structural asset.
- **Read-only reassurance** given its own FAQ entry ("Will this tool make any changes…? …CAMP is a diagnostic tool that is 'read-only'.").
- **Report-vocabulary definitions** — a dedicated entry defining Recommendation / Informational / Improvement / OK.
- **Copy-paste run examples** — every parameter shown as a runnable `Get-CAMPReport …` line.

---

## 2. Inventory

**Legend.** Tracked? = **T** (git-tracked) · **U** (untracked, not ignored) · **I** (ignored, present on disk).
Dispositions: **KEEP / GITIGNORE / RELOCATE→archive / RELOCATE→docs / DELETE / NEEDS-DECISION.**
Grouped rows name every member so nothing is hidden. Homogeneous, clearly-referenced module/test/fixture files are grouped; every extra-scrutiny or non-KEEP item gets its own row.

### 2.1 Module code (repo root == module root)

| Item | Type | What it is | References found (file:line) | Tracked? | Disposition | Rationale |
|---|---|---|---|---|---|---|
| `PurviewPostureAnalyzer.psd1` | module-code | Module manifest (v2.0.0; exports 3 functions) | `.psm1` is `RootModule`; self | T | **KEEP** | Manifest; core. (See §3 for gaps.) |
| `PurviewPostureAnalyzer.psm1` | module-code | Loader: dot-sources `Private/**` + `Public/*`, exports public basenames | Manifest `RootModule` (psd1:2) | T | **KEEP** | Module entry loader. |
| `Public/Connect-PurviewPostureSession.ps1` | module-code | Opens IPPS + EXO read-only sessions | Exported (psd1:12); README:81 | T | **KEEP** | Public entry point. |
| `Public/Disconnect-PurviewPostureSession.ps1` | module-code | Closes sessions | Exported (psd1:13); README:89 | T | **KEEP** | Public entry point. |
| `Public/Invoke-PurviewPostureAnalyzer.ps1` | module-code | Orchestrator: collect→analyze→assemble→render; delta mode | Exported (psd1:14); README:85 | T | **KEEP** | Public entry point. |
| `Private/Collect/*.ps1` (10) | module-code | Read-only collectors + `Invoke-PpaReadCmdlet` wrapper + `PpaNormalize` helpers | Dot-sourced by `.psm1:7`; called by orchestrator; unit-tested | T | **KEEP** | Core; heavily referenced. Members: `Get-PpaAudit`, `Get-PpaCommsCompliance`, `Get-PpaDlp`, `Get-PpaDspmAi`, `Get-PpaEdiscovery`, `Get-PpaInsiderRisk`, `Get-PpaRetention`, `Get-PpaSensitivityLabels`, `Invoke-PpaReadCmdlet`, `PpaNormalize`. |
| `Private/Analyze/*.ps1` (9) | module-code | Per-workload analyzers + coverage model | Dot-sourced `.psm1:7`; called by tools + tests | T | **KEEP** | Core. |
| `Private/Analyze/ppa-coverage-applicability.json`, `ppa-coverage-provenance.json` | module-code (data) | Coverage-matrix applicability + provenance maps | Read by `Get-PpaCoverageModel`; `testday-activation.md:28` | T | **KEEP** | Runtime data for the matrix. |
| `Private/Model/*.ps1` (8) | module-code | Status model, finding/section/snapshot factories, snapshot compare/import/export, `ConvertTo-PpaNormalized` | Dot-sourced `.psm1:7` | T | **KEEP** | Core. |
| `Private/Model/ppa-posture-denylist.json`, `ppa-significant-properties.json`, `ppa-snapshot-schema.json` | module-code (data) | Snapshot redaction denylist, delta-significant properties, snapshot JSON schema | Read by Model layer | T | **KEEP** | Runtime data for snapshot/delta. |
| `Private/Core/*.ps1` (6) | module-code | Run context, error section, section select/delta, license + remediation catalog loaders | Dot-sourced `.psm1:7` | T | **KEEP** | Core. |
| `Private/Render/*.ps1` (6) | module-code | HTML/JSON/delta exporters, coverage-matrix + shared-CSS + redaction helpers | Dot-sourced `.psm1:7`; `PpaHtml.ps1:295` cites the mock as provenance | T | **KEEP** | Core render layer. |

### 2.2 Runtime data (`Data/`)

| Item | Type | What it is | References found (file:line) | Tracked? | Disposition | Rationale |
|---|---|---|---|---|---|---|
| `Data/license-requirements.json` | module-code (data) | Dated tier-requirement annotation map (Purview service description) | `Get-PpaLicenseRequirements.ps1:12`; analyzers `Invoke-PpaDlpAnalyzer.ps1:22`, `…DspmAiAnalyzer.ps1:52`, `…LabelAnalyzer.ps1:33`, `…RetentionAnalyzer.ps1:11`; tools `Build-SampleReports.ps1:61`, `New-DeltaFixturePair.ps1:47`; tests `Analyzer.Dlp:13`, `Analyzer.Sections2:21`, `Analyzer.Sparse:24`, `Render.Polish:35`, `Snapshot:38`; docs README:61,201, `LIMITATIONS.md:68` | T | **KEEP** | Widely referenced dated map; maintenance item, not orphan. |
| `Data/remediation-catalog.json` | module-code (data) | Display-only "How to remediate" prose keyed by check ID | `Get-PpaRemediationCatalog.ps1:2,13`; `CHECK_CATALOG.md:375`; `REMEDIATION_REVIEW.md:64`; `Render.Polish.Tests.ps1:378`; `remediation-rework-spec.md:39,110` | T | **KEEP** | Referenced remediation content. |

### 2.3 Tests (`Tests/` — outside the module root ✔)

| Item | Type | What it is | References found (file:line) | Tracked? | Disposition | Rationale |
|---|---|---|---|---|---|---|
| `Tests/*.ps1` (15) | test | Pester 5 suite: read-only guard, model, render, render-polish, per-analyzer, sparse, collect-contract, coverage, delta, snapshot, module | Self-contained; read fixtures under `Samples/` and `Data/` | T | **KEEP** | Test suite; not packaged. |
| `Tests/Golden/dense-snapshot.json` | test (golden) | Golden snapshot pinning ordering/byte-stability | `Snapshot.Tests.ps1:63,249-251,259-260,264-265` | T | **KEEP** | Golden-file drift guard; deletion breaks tests. |

### 2.4 Samples (`Samples/`) — fixtures vs generated output vs explorations

| Item | Type | What it is | References found (file:line) | Tracked? | Disposition | Rationale |
|---|---|---|---|---|---|---|
| `Samples/sample-normalized.json`, `sample-normalized-dense.json` | test (fixture) | Assembled-normalized fixtures (standard/dense) | `Build-SampleReports.ps1:38,56`; `Render-Sample.ps1:26`; `Render.Tests:14`; `Render.Polish:25,30`; `Module.Tests:71`; `Coverage.Tests:363,417,454,460` | T | **KEEP** | Primary render/test fixtures. |
| `Samples/sample-raw/**` (14 incl. `sparse/`, `labels-autolabel-cases.json`, `autolabel-advancedrule.json`, `snapshot-torture.json`) | test (fixture) | Per-workload raw collector fixtures | `Build-SampleReports.ps1:45-53,63-65,80-83,92`; `Snapshot.Tests:25-32,216,288,367,407`; `Coverage.Tests:21-28,383-385`; `Collect.Contract.Tests:37,187-190,517`; `Analyzer.Dlp:12` | T | **KEEP** | Drive analyzers/snapshot/coverage tests. |
| `Samples/delta-fixtures/*.json` (4: `dense-delta-A/B`, `showcase-delta-A/B`) | test (fixture) | Checked-in delta snapshot pairs | `Build-SampleReports.ps1:147-148`; regenerated + verified by `Delta.Tests.ps1:65` via `New-DeltaFixturePair.ps1` | T | **KEEP** | Delta fixtures + drift check. |
| `Samples/Render-Sample.ps1` | tooling | Older single-fixture preview harness → writes `sample-output/` | Self (`Render-Sample.ps1:2` cites the mock) — **no other caller**; not in README/docs/tests | T | **NEEDS-DECISION** | Superseded in practice by `tools/Build-SampleReports.ps1` (which renders 5 variants + snapshot + delta). Still functional and also emits JSON. Retire, or move under `tools/`? Its committed output is stale (below). |
| `Samples/sample-output/posture-report.html` | build-output | Committed render of the standard fixture | Produced by `Render-Sample.ps1:33`; **no reader references** | T | **GITIGNORE** *(or DELETE)* | Regenerated artifact that is checked in; **currently stale** — it carries CDN `<link>` tags (Bootstrap/Font Awesome), i.e. pre-Wave-5 design, while the live generator is now offline/framework-free. Inconsistent with `Samples/sample-reports/` being gitignored. |
| `Samples/sample-output/posture-report.json` | build-output | Committed JSON export of the standard fixture | Produced by `Render-Sample.ps1:34`; no readers | T | **GITIGNORE** *(or DELETE)* | Same as above — regenerated output under version control. |
| `Samples/sample-output/live-report-full.html` | build-output | A committed "full live report" capture (CDN-era, `live-report-full.html:6-7`) | **None** (`live-report-full` matches nowhere) | T | **NEEDS-DECISION** *(lean DELETE)* | Zero references; **not** produced by any current script; stale CDN-based capture superseded by the offline generator. Only value is as a browsable artifact — but it misrepresents current output. |
| `Samples/sample-reports/**` (24: 6 sample HTML, delta HTML ×2, snapshot JSON ×16) | build-output | Output of `tools/Build-SampleReports.ps1` | `.gitignore:354`; written by `Build-SampleReports.ps1` | I | **KEEP (as-is)** | Correctly gitignored already; present on disk only. No action. |
| `Samples/design-explorations/**` (14) | design-mock | Rejected/accepted report re-skins, build scripts, rationale/log/comparison docs | Internal cross-refs only (e.g. `feasibility-map.md:20`); briefs in §2.6 point at it | U | **NEEDS-DECISION** (DELETE vs RELOCATE→archive) | Design workspace; the winning "A-v2/polished" design already **shipped** to the generator (`8c5c95a`, `46048e6`). Never committed. `RATIONALE.md`/`POLISH-LOG.md` have provenance/browse value → archive; otherwise delete. |

### 2.5 Tooling (`tools/`)

| Item | Type | What it is | References found (file:line) | Tracked? | Disposition | Rationale |
|---|---|---|---|---|---|---|
| `tools/Build-SampleReports.ps1` | tooling | Renders 5 fixture reports + snapshot + 2 deltas into gitignored `sample-reports/` | README:143,219; `delta-report.md:68`; specs `wave5:46`, `remediation-rework:132`, `report-polish:159,174`, `wave4:7,398,412`; `feasibility-map.md:20` | T | **KEEP** | Documented sample harness; the render validation loop. |
| `tools/New-DeltaFixturePair.ps1` | tooling | Derives delta fixture A/B pairs from mutation tables | `Delta.Tests.ps1:65`; `wave4-…-spec.md:356` | T | **KEEP** | Test-referenced fixture generator. |
| `tools/delta-fixture-mutations.json`, `tools/delta-fixture-mutations-showcase.json` | tooling (data) | Explicit mutation tables consumed by `New-DeltaFixturePair.ps1` | `New-DeltaFixturePair.ps1:79-80` | T | **KEEP** | Inputs to the fixture generator. |

### 2.6 Docs (`docs/`) — classified individually

| Item | Type | What it is | References found (file:line) | Tracked? | Disposition | Rationale |
|---|---|---|---|---|---|---|
| `docs/delta-report.md` | doc-living | User guide for the delta report | README:167 | T | **KEEP** | Living, README-linked. |
| `docs/REMEDIATION_REVIEW.md` | doc-living | Human-review checklist for remediation drafts | README:141; `CHECK_CATALOG.md:392` | T | **KEEP** | Living, referenced. |
| `docs/KEY_SOURCES.md` | doc-living (reference) | Snapshot identity/keying contract (Guid→Identity→Name) | Documents current `PpaNormalize`/snapshot behavior; no code ref | T | **KEEP** | Describes current contract; useful reference. Origin: Wave 4. |
| `docs/testday-activation.md` | doc-living (checklist) | Deferred-until-live-tenant checklist; item 3 still open | Cross-refs specs; no code ref | T | **KEEP** | Open action items; still live. |
| `docs/specs/ai-findings-build-spec.md` | doc-living (provenance) | AI-findings cmdlet provenance record (verified/doc-grounded/unverified) | `CHECK_CATALOG.md:72,299`; README:72; `testday-activation.md:27` | T | **KEEP** | Actively cited as the AI provenance source of record. |
| `docs/specs/remediation-rework-spec.md` | doc-historical | Wave 3.1 build spec | Historical; `remediation-catalog` refs | T | **KEEP** *(opt. RELOCATE→archive)* | Frozen build spec; already segregated under `specs/`. |
| `docs/specs/report-polish-build-spec.md` | doc-historical | Wave 3 build spec | Historical | T | **KEEP** *(opt. RELOCATE→archive)* | Frozen build spec. |
| `docs/specs/wave4-snapshot-delta-matrix-spec.md` | doc-historical | Wave 4 build spec | Historical (memory cites it) | T | **KEEP** *(opt. RELOCATE→archive)* | Frozen build spec. |
| `docs/specs/wave5-cleanup-spec.md` | doc-historical | Wave 5 build spec | Historical | T | **KEEP** *(opt. RELOCATE→archive)* | Frozen build spec. |
| `docs/port-to-generator-brief.md` | doc-historical (design brief) | "Port polished design to generator & ship" brief | Points at `design-explorations/`; work done (`46048e6`/`8c5c95a`) | U | **NEEDS-DECISION** (DELETE vs archive) | Spent scaffolding; never committed; work shipped. |
| `docs/ux-polish-brief.md` | doc-historical (design brief) | "Refine don't redesign" polish brief | Superseded — polish shipped | U | **NEEDS-DECISION** (DELETE vs archive) | Spent; never committed. |
| `docs/ux-redesign-brief.md` | doc-historical (design brief) | 3-reskin redesign brief (reskins **rejected**) | Superseded — rejected | U | **NEEDS-DECISION** (DELETE vs archive) | Spent; never committed. |

### 2.7 Legacy (`legacy/`)

| Item | Type | What it is | References found (file:line) | Tracked? | Disposition | Rationale |
|---|---|---|---|---|---|---|
| `legacy/**` (34 files: `CAMP.psm1`, `Checks/`, `Outputs/`, `Utilities/`, `Remediation/`, `Templates/`, `DLPImprovementActions/`, `RunCAMPReport.ps1`, `README.md`) | doc-historical (superseded code) | The original OfficeDev/CAMP engine, kept "for reference during transition" | **Not dot-sourced** (`.psm1` loads only `Private/`+`Public/`); **not** imported/called by any module code or test (all "legacy" grep hits are fixture *policy names* like "Legacy DLP", not `legacy/` paths). `legacy/README.md:21` links to a **missing** `MODERNIZATION_PLAN.md`. | T | **RELOCATE→archive** | Frozen ancestor, explicitly "do not run", zero runtime/test coupling. Retain for provenance (its README documents what was deliberately removed). Fix/remove the dangling `MODERNIZATION_PLAN.md` link on relocation. |

### 2.8 Root docs

| Item | Type | What it is | References found (file:line) | Tracked? | Disposition | Rationale |
|---|---|---|---|---|---|---|
| `README.md` | doc-living | Project README | self | T | **KEEP** *(restructure — see §5)* | Living; needs the roles matrix + scope section + clone step. |
| `CHECK_CATALOG.md` | doc-living | The domain spec (every check, cmdlet, status rule) | `PLAN.md:9`; README (project layout); still edited through Wave 6 | T | **KEEP** | Actively maintained source of truth. |
| `PLAN.md` | doc-living / historical | The build plan; still cited for decisions (e.g. D9, "two fixed targets") | `CHECK_CATALOG.md`; README:223; `Connect-…:7` (D9) | T | **KEEP** | Largely historical now the build is done, but still the decision-of-record. |
| `LIMITATIONS.md` | doc-living | What isn't assertable read-only, and why | README:189,198,223; `CHECK_CATALOG.md` (Verify rows) | T | **KEEP** | Living, referenced. |

### 2.9 Community-health & licensing

| Item | Type | What it is | References found (file:line) | Tracked? | Disposition | Rationale |
|---|---|---|---|---|---|---|
| `LICENSE` | community-health | MIT license (preserved from CAMP) | `NOTICE:12`; README:7 | T | **KEEP** | Required. |
| `NOTICE` | community-health | Attribution + differences-from-CAMP | README:7 | T | **KEEP** | Accurate, current; feeds README §9. |
| `CODE_OF_CONDUCT.md` | community-health | Microsoft Open Source CoC | CAMP-inherited | T | **KEEP** *(review wording)* | Points at `opencode@microsoft.com`; fine to keep, but this is a community fork, not a Microsoft repo. |
| `SECURITY.md` | community-health | Vuln-reporting policy | CAMP-inherited | T | **KEEP** *(FLAG: content inaccurate)* | Directs reports to **Microsoft MSRC / secure@microsoft.com** — contradicts `NOTICE` ("NOT a Microsoft product, NOT supported by Microsoft"). Needs de-Microsoft-ification. |
| `SUPPORT.md` | community-health | Support channels | CAMP-inherited template | T | **KEEP** *(FLAG: unedited)* | Still contains the boilerplate `TODO: maintainer has not yet edited this file` and `REPO MAINTAINER: INSERT INSTRUCTIONS HERE` placeholders. Must be edited before publish. |

### 2.10 Assets, design mock, config

| Item | Type | What it is | References found (file:line) | Tracked? | Disposition | Rationale |
|---|---|---|---|---|---|---|
| `Image/logo.jpg` | asset | 10 KB logo image inherited from CAMP | **None.** The string `.jpg` and path `Image/` appear **nowhere** in the repo. The report renders a `.logo-ph` **placeholder box** ("Client logo (250×150)"), never an image (`Export-PpaHtmlReport.ps1:88`, `PpaHtml.ps1:465`). | T | **NEEDS-DECISION** *(lean DELETE)* | Dead weight: current generator never reads it. Keep only if a real logo-embedding feature is planned (CAMP's "replace `Image/logo.jpg`" pattern was dropped for a placeholder). |
| `posture-report-mock-v5.html` | design-mock | The original look+content "fixed target" (56 KB, CDN-based) | `CHECK_CATALOG.md:3`; `PLAN.md:9,263,267`; `Render-Sample.ps1:2` (comment); `PpaHtml.ps1:295` (provenance comment). **No snapshot/golden/drift-guard test pins it** — grep across `Tests/` finds zero references. | T | **NEEDS-DECISION** | *Extra-scrutiny result:* **not** test-referenced, so it is not a runtime/CI dependency and *could* move. **But** it is cited as a build target by two living docs (`CHECK_CATALOG`, `PLAN`) and two code comments; relocating requires updating those 6 references first. The live report has since diverged to the A-v2 design, making the mock historical. → RELOCATE→archive *after* refactoring the 6 refs, or KEEP as a pinned historical target. |
| `.gitignore` | config | Ignore rules (VS boilerplate + `Outputs/` + `Samples/sample-reports/`) | self | T | **KEEP** | Active. Candidate additions noted in triage. |
| `.claude/settings.local.json` | config | Dev-local Claude Code settings | Ignored via **global** `~/.config/git/ignore` pattern `**/.claude/settings.local.json` (not this repo's `.gitignore`) | I | **KEEP (as-is)** | Correctly ignored; never tracked. No `.claude/` content is in the repo tree. |

### 2.11 Referenced-but-missing (findings, not files)

| Missing item | Referenced by | Impact |
|---|---|---|
| `CONTRIBUTING.md` | Target README skeleton item 10 | No contributor guide exists; README has no Contributing section. |
| `MODERNIZATION_PLAN.md` | `legacy/README.md:21` (`../MODERNIZATION_PLAN.md`) | Dangling link. Either the doc was renamed to `PLAN.md`/`NOTICE` or never created. Fix the link or create the file. |

---

## 3. Packaging state (for the later publish session — report only)

**`PurviewPostureAnalyzer.psd1`**

| Field | Value |
|---|---|
| `RootModule` | `PurviewPostureAnalyzer.psm1` |
| `ModuleVersion` | `2.0.0` |
| `GUID` | `08016980-865c-4ab2-8df2-4c60e235189f` |
| `PowerShellVersion` | `5.1` |
| `FunctionsToExport` | `Connect-PurviewPostureSession`, `Disconnect-PurviewPostureSession`, `Invoke-PurviewPostureAnalyzer` |
| `CmdletsToExport` / `VariablesToExport` / `AliasesToExport` | all `@()` (empty) — good hygiene |
| `RequiredModules` | **ABSENT** |
| `FileList` | **ABSENT** |
| `PrivateData.PSData.ProjectUri` | `https://github.com/OfficeDev/Configuration-Analyzer-for-Microsoft-Purview` (points at **CAMP**, not `github.com/yazarmyint/PurviewPostureAnalyzer`) |
| Other path refs | none |

**`PurviewPostureAnalyzer.psm1`** — loads `Get-ChildItem Private -Recurse -Filter *.ps1` then `Public/*.ps1`, dot-sources each, and `Export-ModuleMember -Function` the **Public basenames only**. Clean convention-based loader; no hard-coded import list to drift.

**Manifest ↔ Public parity:** exports (3) exactly match the three `Public/*.ps1` files — **no missing or extra exports.**

**Tests location:** `Tests/` is a sibling of the module root (not under `Public/`/`Private/`) — **good for publishing.**

**Publish-hygiene findings (flag for the publish session):**

1. **No `FileList` and no staging/build script in `tools/`.** Publish hygiene is controlled by *neither* mechanism. Consequently **`Publish-Module -Path .` from repo root would package the entire tree** — including `legacy/` (the old CAMP engine), `docs/`, `Tests/`, `Samples/` (fixtures + committed sample HTML), `posture-report-mock-v5.html`, `Image/logo.jpg`, untracked `design-explorations/`, and even this `INVENTORY-ANALYSIS.md`. A `FileList` allowlist or a `tools/Build-Package.ps1` staging step is needed before publishing.
2. **`RequiredModules` is missing.** The tool depends on **ExchangeOnlineManagement** (provides `Connect-IPPSSession`, `Connect-ExchangeOnline`, and proxies every `Get-*` compliance/EXO cmdlet). It is documented in README but not declared in the manifest, so import won't surface/auto-load the dependency. Add `RequiredModules = @('ExchangeOnlineManagement')`. (No Graph dependency — Graph was removed by decision D9, so the single-module list is correct and complete.)
3. **`ProjectUri` points at the upstream CAMP repo**, not this project's origin. Update before publish.
4. **Nothing is on `main`** (see §0) — resolve branch promotion before any publish-from-main flow.

---

## 4. Cmdlet → minimum-role mapping

Derived from the collectors (`Private/Collect/*.ps1`) and `Public/Connect-PurviewPostureSession.ps1`. Two sessions only; **no Microsoft Graph**. Every read runs through `Invoke-PpaReadCmdlet`, whose guardrail refuses any verb outside `Get/Search/Test/Resolve` (`Invoke-PpaReadCmdlet.ps1:22`), and degrades one finding (never the run) on access-denied.

| Workload (collector) | Read-only cmdlet(s) | Session | Minimum role for read access | Global Reader suffices? |
|---|---|---|---|---|
| Sensitivity Labels (`Get-PpaSensitivityLabels`) | `Get-Label`, `Get-LabelPolicy`, `Get-AutoSensitivityLabelPolicy`, `Get-AutoSensitivityLabelRule` | IPPS (Security & Compliance) | Global Reader **or** Compliance Administrator / Compliance Data Administrator (View-Only IP roles) | **Yes** |
| └ Azure RMS (LABELS-05) | `Get-IRMConfiguration` (`Get-PpaSensitivityLabels.ps1:93,200`) | **Exchange Online** | Global Reader **or** EXP View-Only Organization Management | **Yes** |
| Data Loss Prevention (`Get-PpaDlp`) | `Get-DlpCompliancePolicy`, `Get-DlpComplianceRule` | IPPS | Global Reader **or** Compliance Admin / Compliance Data Admin | **Yes** |
| Retention & Records (`Get-PpaRetention`) | `Get-RetentionCompliancePolicy`, `Get-RetentionComplianceRule`, `Get-AdaptiveScope` | IPPS | Global Reader **or** Compliance Admin | **Yes** |
| Audit (`Get-PpaAudit`) | `Get-AdminAuditLogConfig`, `Get-OrganizationConfig` | **Exchange Online** | Global Reader **or** View-Only Audit Logs / View-Only Organization Management | **Yes** |
| eDiscovery (`Get-PpaEdiscovery`) | `Get-ComplianceCase` | IPPS | eDiscovery Manager/Administrator **or** Compliance Administrator | **No** (plain Global Reader can't enumerate cases — CAMP matrix agrees) |
| Insider Risk (`Get-PpaInsiderRisk`) | `Get-InsiderRiskPolicy` | IPPS | **Insider Risk Management** role group (IRM Admin/Analyst/Investigator) | **No** |
| Communication Compliance (`Get-PpaCommsCompliance`) | `Get-SupervisoryReviewPolicyV2` (+ `Get-SupervisoryReviewRule`) | IPPS | **Communication Compliance** role group | **No** |
| DSPM for AI · Copilot (`Get-PpaDspmAi`) | `Get-DlpCompliancePolicy`, `Get-DlpComplianceRule`, `Get-DspmPolicy`, `Get-AppRetentionCompliancePolicy`, `Get-RetentionCompliancePolicy`, `Get-SupervisoryReviewPolicyV2`, `Get-SupervisoryReviewRule` | IPPS | Compliance Admin for the DLP/DSPM/retention reads; the **CC sub-reads additionally need the Communication Compliance role group** | **Partial** |

**Least-privilege summary (feeds README matrix + `RequiredModules`):**
- A single **Global Reader** covers Labels, DLP, Retention, Audit, Azure RMS — i.e. the E3-baseline workloads — and the tool gracefully degrades IRM/CC/eDiscovery/AI-CC to transparency/Verify rows rather than failing.
- Full coverage requires **Global Reader + Insider Risk Management role group + Communication Compliance role group + an eDiscovery role**. This matches the README prose (Compliance Reader/Global Reader plus CC and IRM role groups) and CAMP's matrix (Global Reader = No for IRM/CC/eDiscovery).
- **Global Admin is not required** (design goal, README:45).
- Module dependency implied by every cmdlet above: **ExchangeOnlineManagement only** → confirms the `RequiredModules` fix in §3.

---

## 5. README structure analysis (CAMP vs PPA)

**PPA README current section order:**
1. Title + one-line + disclaimer blockquote + "eight workloads" line
2. `## What it does and does not do`
3. `## Requirements` (+ `### Tenant licensing`)
4. `## How to run` (+ `### Run profiles`, `### Redaction`, `### Report features (Wave 3)`, `### Snapshots and the delta report`)
5. `## How to read the statuses`
6. `## Known limitations`
7. `## Project layout`

**CAMP README order:** Overview → What is it → Why → **What's in scope** → How do I run it (**Pre-Requisites + roles matrix**) → Install Guide → License (OSS components) → FAQ (read-only + **status vocabulary**) → Contributing → Trademark.

### Gap analysis vs the agreed target skeleton

| # | Target section | Status in PPA | Note |
|---|---|---|---|
| 1 | Title + one-line overview | **Present** | README:1-3. |
| 2 | What it is / does (read-only, `Connect-IPPSSession`+`Get-*`, HTML report) | **Present** | "What it does and does not do" (README:16-31). |
| 3 | Read-only safety statement, **up front** | **Present but understated** | It's a bullet inside §2 plus the `ReadOnlyGuard` note; CAMP gives it a prominent standalone reassurance. Consider elevating to its own short callout near the top. |
| 4 | What's in scope (from `CHECK_CATALOG`; AI called out) | **Misplaced / thin** | Only the one-line "eight workloads" list (README:11-12). No dedicated scope section enumerating the check families; AI is mentioned but not broken out. Add a "What's in scope" section sourced from `CHECK_CATALOG.md`. |
| 5 | What the report looks like (sample + severity vocab + coverage matrix + snapshot/delta) | **Partial** | Severity vocabulary **present** (`## How to read the statuses`, 5-status table); snapshot/delta **present**. **Missing:** a sample screenshot or link to a browsable sample report, and any mention of the coverage matrix in this context. (Note the committed `sample-output/` HTML is stale — don't link it until regenerated.) |
| 6 | Prerequisites (licensing; PS 5.1/7; EXO/IPPS module; permissions) | **Present** | `## Requirements` + `### Tenant licensing` — well bundled, CAMP-style. |
| 7 | **Roles & permissions matrix** (role × check-family, Yes/Partial/No) | **Missing** | Biggest gap. PPA has prose about CC/IRM role groups but no matrix. §4 above provides the raw material; CAMP's table (Step 1) is the structural model. |
| 8 | Quickstart (CLONE → import → run generator, **today**; not `Install-Module`) | **Partial** | `Import-Module .\…psd1` + Connect + Invoke shown (README:78-90) and correctly **avoids** `Install-Module`. **Missing:** the explicit `git clone` step. Add clone-then-import. |
| 9 | Licensing / attribution (derivation + license + OSS components) | **Partial** | Disclaimer + LICENSE/NOTICE **present**. **Missing:** explicit open-source-components statement. Since the report is now offline/framework-free (Wave 5), the honest statement may be "no bundled third-party runtime components" — worth saying, since CAMP listed Bootstrap/Font Awesome/clipboard.js. |
| 10 | Contributing / dev conventions → `CONTRIBUTING.md` | **Missing** | No Contributing section and no `CONTRIBUTING.md` file (§2.11). |

### Divergences from CAMP to **preserve** (do not copy CAMP content)

- **Strictly read-only, no remediation-as-automation.** CAMP ships remediation scripts that `New-DlpCompliancePolicy` and `Install-Module -force`; PPA deliberately removed all of that (`NOTICE`, `legacy/README.md`). Remediation in PPA is **display-only prose**, no PowerShell.
- **Clone-and-run today, not `Install-Module`.** The module is unpublished (nothing on `main`); the README must document clone→import, and must **not** document `Install-Module PurviewPostureAnalyzer`. Module install is a future session.
- **Scope = PPA's own `CHECK_CATALOG`** (8 Purview workloads with the PPA check IDs and the 5-status model incl. *Verify manually*), **not** CAMP's 8-solution taxonomy or its 4-status vocabulary.
- **No Graph, no telemetry, no geo/DoD parameters** — omit CAMP's Geo/Solution/ExchangeEnvironmentName/TurnOffDataCollection parameter docs.

---

## Triage summary (group by recommended disposition)

**KEEP (in place — referenced or core):**
- All module code: `.psd1`, `.psm1`, `Public/*` (3), `Private/**` (`Collect` 10, `Analyze` 9 + 2 JSON, `Model` 8 + 3 JSON, `Core` 6, `Render` 6).
- Runtime data: `Data/license-requirements.json`, `Data/remediation-catalog.json`.
- Tests: `Tests/*.ps1` (15) + `Tests/Golden/dense-snapshot.json`.
- Fixtures: `Samples/sample-normalized*.json`, `Samples/sample-raw/**`, `Samples/delta-fixtures/*`.
- Tooling: `tools/Build-SampleReports.ps1`, `tools/New-DeltaFixturePair.ps1`, `tools/delta-fixture-mutations*.json`.
- Living docs: `README.md` (restructure), `CHECK_CATALOG.md`, `PLAN.md`, `LIMITATIONS.md`, `docs/delta-report.md`, `docs/REMEDIATION_REVIEW.md`, `docs/KEY_SOURCES.md`, `docs/testday-activation.md`, `docs/specs/ai-findings-build-spec.md`.
- Community-health/licensing: `LICENSE`, `NOTICE`, `CODE_OF_CONDUCT.md`, plus `SECURITY.md` & `SUPPORT.md` **(flagged: edit content, don't move)**.
- Config: `.gitignore`, `.claude/settings.local.json` (already ignored).
- Historical build specs `docs/specs/{remediation-rework,report-polish,wave4-…,wave5-cleanup}.md` — keep in place (optionally archive).

**GITIGNORE (stop tracking regenerated output):**
- `Samples/sample-output/posture-report.html`, `Samples/sample-output/posture-report.json` — regenerated by `Render-Sample.ps1`; currently **stale** (CDN-era). Add `Samples/sample-output/` to `.gitignore` **or** DELETE if `Render-Sample.ps1` is retired. (`Samples/sample-reports/` is already correctly ignored.)

**RELOCATE → archive/ (frozen historical, unreferenced by runtime/tests):**
- `legacy/**` — the old CAMP engine ("do not run"); fix its dangling `MODERNIZATION_PLAN.md` link on move.
- *(Optional)* the four Wave build specs under `docs/specs/` and — **only after refactoring its 6 doc/comment references** — `posture-report-mock-v5.html`.

**RELOCATE → docs/ (living doc, misplaced):**
- None. (Living docs are already under `docs/` or root.)

**DELETE (candidate true orphans — confirm intent):**
- `Samples/sample-output/live-report-full.html` — zero references, stale CDN capture, not regenerated by any script (also viable as NEEDS-DECISION if kept as a browsable artifact).

**NEEDS-DECISION (explain the fork):**
- `posture-report-mock-v5.html` — historical design target **or** pinned reference. Not test-coupled, so movable, but cited by `CHECK_CATALOG:3`, `PLAN:9/263/267`, `Render-Sample.ps1:2`, `PpaHtml.ps1:295`. Fork: (a) KEEP as the pinned look/content target, or (b) RELOCATE→archive after updating those 6 references.
- `Image/logo.jpg` — DELETE (unreferenced; report uses a placeholder box) **or** KEEP as a branding stub if a logo-embed feature is planned.
- `Samples/Render-Sample.ps1` — retire (superseded by `tools/Build-SampleReports.ps1`) **or** keep as the JSON-emitting single-fixture harness; if kept, regenerate its stale output.
- `Samples/design-explorations/**` (untracked, 14) — DELETE (spent scaffolding, work shipped) **or** RELOCATE→archive for the `RATIONALE.md`/`POLISH-LOG.md` provenance.
- `docs/{port-to-generator,ux-polish,ux-redesign}-brief.md` (untracked) — DELETE (spent, work shipped/rejected) **or** RELOCATE→archive with the design-explorations set.

**Cross-cutting actions surfaced (not file dispositions):**
- Add `RequiredModules = @('ExchangeOnlineManagement')` to the manifest; fix `ProjectUri`.
- Add a `FileList` allowlist **or** a `tools/` packaging/staging script before any `Publish-Module` (today it would package the whole tree).
- Fix `SECURITY.md` (points vuln reports to Microsoft) and `SUPPORT.md` (unedited template) to match the community-fork reality in `NOTICE`.
- Create `CONTRIBUTING.md`; resolve the missing `MODERNIZATION_PLAN.md` link.
- Promote `feature/report-a-v2-design` to `main` (and fast-forward `origin/feature/report-a-v2-design`) before the publish session.

---

*End of report. Nothing in the repository was created, modified, moved, or deleted except this file. Recommendations await human triage.*
