# CAMP v2 — Check Catalog

The domain spec for the modernized report. Every finding in `posture-report-mock-v5.html`
is transcribed here as: **what it reads** (cmdlet + property), **how it's shown** (table columns),
and **how the status is decided** (the OK / Improvement / Recommendation / Informational / Verify logic).

This is the second fixed target (alongside the mock) that the Claude Code session builds toward.
You own the domain columns marked below; the cmdlet layer is the one place to sanity-check.

---

## How to read an entry

```
ID          — stable identifier (used in code + JSON output)
Reads       — the read-only cmdlet(s) and the property that matters
Columns     — the drill-down table headers, mapped to the property behind each
Status      — the rule that assigns the verdict
License     — E5 gate, if any (drives "not available under current licensing")
Links       — Learn-more targets shown in the drill-down
```

### Confidence markers on cmdlets

- **✓ verified** — pulled from the original CAMP collection layer or confirmed on Microsoft Learn.
- **⚠ confirm** — newer surface; the cmdlet/property is my best current understanding and should be
  validated against the tenant during the Code build before it's relied on.

### Status model (unchanged from the mock)

`OK` · `Improvement` · `Recommendation` · `Informational` · `Verify manually`.
`Verify manually` is reserved for the genuinely un-assertable from a session — not a fallback for
whole areas. E5-tier areas on a sub-E5 tenant report **Informational (not licensed)**, never a gap.

### Connection & safety (applies to every check)

- **Security & Compliance PowerShell** (`Connect-IPPSSession`) — labels, DLP, retention, IRM,
  comms compliance, eDiscovery, DSPM-for-AI policies.
- **Exchange Online** (`Connect-ExchangeOnline`) — audit config, organization config.
- **Microsoft Graph** (`Connect-MgGraph`, read scopes) — licensing / Copilot service-plan presence.
- **Read-only:** collectors call `Get-*` only. No `Set-/New-/Remove-/Enable-/Disable-`. This is
  the one rule the Code session must never break, and it's worth an automated guard in the repo.

---

## 01 · Sensitivity Labels

**Section reads:** `Get-Label` ✓, `Get-LabelPolicy` ✓, `Get-AutoSensitivityLabelPolicy` ✓
**Collector plan:** pull all three once into `normalized/labels.json`; the four analyzers below read from that.

### LABELS-01 — Taxonomy is defined
- **Reads:** `Get-Label` → `Name`, `Priority`, `ContentType` (scope), `ParentId` (sub-labels)
- **Columns:** Label → `Name` · Priority → `Priority` · Scope → `ContentType` · Status
- **Status:** labels present → **Informational** (inventory). Zero labels → **Improvement** (no taxonomy).
- **Links:** Purview portal — Information Protection; Overview of sensitivity labels.

### LABELS-02 — Labels are published to users
- **Reads:** `Get-LabelPolicy` → `Name`, `Labels`, `ExchangeLocation`/`ModernGroupLocation`, `Enabled`
- **Columns:** Label Policy → `Name` · Labels → `Labels` · Assigned To → location props · Status
- **Status:** ≥1 enabled policy scoped to users → **OK**. Labels exist but no enabled policy → **Improvement**.
- **Links:** Create and publish sensitivity labels.

### LABELS-03 — Auto-labeling is not enforcing
- **Reads:** `Get-AutoSensitivityLabelPolicy` → `Name`, `Mode`, conditions
- **Columns:** Auto-labeling Policy → `Name` · Conditions (SITs) → rule conditions · Mode → `Mode` · Status
- **Status:** `Mode = Enforce` → **OK**. `Mode = TestWithNotifications`/`TestWithoutNotifications` (simulation) →
  **Improvement**. No auto-labeling policy at all → **Recommendation**.
- **Links:** Purview portal — Information Protection; Compliance Manager; Overview of sensitivity labels;
  How to apply a sensitivity label to content automatically.

### LABELS-04 — No container labels for Teams / Sites / Groups
- **Reads:** `Get-Label` → `ContentType` (does it include `Site`, `UnifiedGroup`?)
- **Columns:** Container type · Coverage · Status
- **Status:** container-scoped labels exist and are applied → **OK**. None → **Recommendation**.
- **Links:** Use sensitivity labels to protect containers (groups & sites).

---

## 02 · Data Loss Prevention

**Section reads:** `Get-DlpCompliancePolicy` ✓ (`.Mode`, `*Location`), `Get-DlpComplianceRule` ✓
(SITs, actions), `Get-DlpSensitiveInformationType` ✓
**Note:** `.Mode` values are `Test` / `AuditAndNotify` / `Enforce` — the core enforce-vs-test signal.

### DLP-01 — DLP policies exist (enforcing vs. test)
- **Reads:** `Get-DlpCompliancePolicy` → `Name`, `Mode`, `*Location`; `Get-DlpComplianceRule` → SITs, `Disabled`
- **Columns:** DLP Policy → `Name` · Sensitive Information Type → rule SITs · Remarks → mode + locations · Status
- **Status (per policy):** `Mode = Enforce` → **OK**. `Mode = Test`/`AuditAndNotify` → **Improvement**
  (remark: detects but does not block). Section-level: zero policies → **Improvement**.
- **Links:** Purview portal — DLP; Learn about data loss prevention.

### DLP-02 — Teams is not in scope
- **Reads:** `Get-DlpCompliancePolicy` → `TeamsLocation` across all policies
- **Columns:** Location · In scope · Status  (rows: Exchange, SharePoint, OneDrive, Teams)
- **Status:** Teams absent from every policy → **Improvement**. Present in ≥1 → **OK** for that row.
- **Links:** Use DLP with Microsoft Teams.

### DLP-03 — Endpoint DLP is not configured
- **Reads:** `Get-DlpCompliancePolicy` → `EndpointDlpLocation` ✓; **device onboarding count ⚠ confirm**
  (not cleanly in S&C PowerShell — likely Graph / Defender endpoint inventory, or report as Verify)
- **Columns:** Configuration · Setting · Status
- **Status:** no endpoint location in any policy **and** 0 devices onboarded → **Improvement**. If device
  count is not retrievable read-only, that row becomes **Verify manually** rather than a false 0.
- **Links:** Learn about Endpoint DLP.

### DLP-04 — HIPAA template detectors reduced under sub-E5
- **Reads:** `Get-DlpComplianceRule` → referenced SITs; cross-ref `Get-DlpSensitiveInformationType`
  + detected license to flag named-entity SITs that need E5 **⚠ confirm** the SKU-to-SIT mapping
- **Columns:** Detector (SIT) · Availability at tenant SKU · Status
- **Status:** named-entity / enhanced detectors unavailable at tenant tier → **Improvement** on those rows;
  base detectors active → **OK**. Remark states the functional-detector count.
- **Links:** DLP policy reference.

---

## 03 · Retention & Records

**Section reads:** `Get-RetentionCompliancePolicy` ✓ (`.Mode`, `.Enabled`, scope), `Get-RetentionComplianceRule` ✓
(labels, auto-apply conditions), `Get-AdaptiveScope` ✓

### RET-01 — Retention policies & labels (inventory)
- **Reads:** `Get-RetentionCompliancePolicy` → `Name`, scope; `Get-RetentionComplianceRule` → labels
- **Columns:** Retention Policy → `Name` · Labels → rule labels · Remarks → scope type · Status
- **Status:** present → **Informational**. Zero policies → **Improvement**.
- **Links:** Learn about retention policies & labels.

### RET-02 — No adaptive scopes
- **Reads:** `Get-AdaptiveScope` (count) + policies using `AdaptiveScopeLocation`
- **Columns:** Scope type · Count · Status
- **Status:** 0 adaptive scopes and all policies static → **Improvement**. ≥1 adaptive → **OK** row.
- **Links:** Adaptive vs. static scopes.

### RET-03 — Retention labels are manual-apply only
- **Reads:** `Get-RetentionComplianceRule` → auto-apply condition (SIT / KQL / trainable) presence
- **Columns:** Retention label · Auto-apply rule · Status
- **Status:** labels with no auto-apply condition → **Improvement**. Auto-apply present → **OK**.
- **Links:** Auto-apply retention labels.

---

## 04 · Insider Risk Management  *(E5)*

**Section reads:** `Get-InsiderRiskPolicy` ✓, `Get-InsiderRiskManagementSettings` ✓
**License:** M365 E5 / E5 Compliance / IRM add-on. Detect via Graph service plan **⚠ confirm**, or treat
cmdlet-unavailable / access-denied as "not licensed."

### IRM-01 — No IRM policies detected
- **Reads:** `Get-InsiderRiskPolicy` (count); license signal
- **Columns:** Configuration · Setting · Status
- **Status:** unlicensed → **Informational (not licensed)**, no coverage verdict. Licensed **and** 0 policies →
  **Improvement**. Licensed with policies → per-policy inventory.
- **Links:** Learn about Insider Risk Management.

### IRM-02 — Consider licensing for departing-employee risk
- **Reads:** n/a (advisory, fires only when IRM absent)
- **Status:** **Recommendation** — licensing + HR/Legal alignment, not a config action.
- **Links:** IRM policy templates.

### IRM-03 — Risky AI usage template coverage *(Wave 2)*
- **Reads:** `Get-InsiderRiskPolicy` → `InsiderRiskScenario` ✓ (template identifier, verified
  2026-07-02). Exact risky-AI enum **⚠ unverified** — pattern-matched with word-boundary care,
  policy `Name` as corroboration only; tighten to `-eq` once observed live.
- **Columns:** IRM Policy · Scenario · Workloads · Created · Status
- **Status:** no AI-scenario policy (readable) → **Recommendation** (prompt-injection /
  protected-material signals unscored). Present → **OK** inventory. Unreadable → skipped
  (IRM-01's Verify-manually covers the section; absence is never asserted from a failed read).
- **Note:** the collector excludes the `InsiderRiskScenario = TenantSetting` pseudo-policy
  (`IRM_Tenant_Setting_<guid>`) from **all** IRM counts and inventories — verified 2026-07-02;
  a zero-policy tenant otherwise reports as having one.
- **Links:** IRM policy templates.

---

## 05 · Audit

**Section reads:** `Get-AdminAuditLogConfig` ✓ (`UnifiedAuditLogIngestionEnabled`), `Get-OrganizationConfig` ✓
(Exchange Online). Premium retention via license **⚠ confirm**.

### AUD-01 — Unified audit logging is enabled
- **Reads:** `Get-AdminAuditLogConfig` → `UnifiedAuditLogIngestionEnabled`
- **Columns:** Configuration · Setting · Status
- **Status:** `True` → **OK**. `False` → **Improvement**.
- **Links:** Learn about auditing solutions.

### AUD-02 — Ingestion / latency not confirmable this session
- **Reads:** none reliable from a config read
- **Status:** **Verify manually** — "enabled" ≠ "ingesting on time." (The one legitimate manual flag.)
- **Links:** Search the audit log.

### AUD-03 — Audit Premium (long-term retention) not licensed
- **Reads:** license signal
- **Status:** not licensed → **Informational**.
- **Links:** Audit (Premium).

---

## 06 · eDiscovery

**Section reads:** `Get-ComplianceCase` ✓ (`Name`, `Status`). Premium via license **⚠ confirm**.

### ED-01 — eDiscovery in use (cases)
- **Reads:** `Get-ComplianceCase` → `Name`, `Status`
- **Columns:** Case Name → `Name` · Case Status → `Status` · Status
- **Status:** inventory → **Informational** (no maturity judgment).
- **Links:** Learn about eDiscovery.

### ED-02 — eDiscovery Premium not licensed
- **Reads:** license signal
- **Status:** not licensed → **Informational**.
- **Links:** eDiscovery capabilities by tier.

---

## 07 · Communication Compliance  *(E5)*

**Section reads:** `Get-SupervisoryReviewPolicyV2` ✓. License-gated as IRM above.

### CC-01 — No Communication Compliance policies detected
- **Reads:** `Get-SupervisoryReviewPolicyV2` (count); license signal
- **Columns:** Configuration · Setting · Status
- **Status:** unlicensed → **Informational (not licensed)**. Licensed **and** 0 policies → **Improvement**.
- **Links:** Learn about Communication Compliance.

---

## 08 · DSPM for AI · Copilot Data Security  *(NEW — 2026, Wave 2 expanded)*

**Section reads (all over `Connect-IPPSSession`):** `Get-DlpCompliancePolicy` ✓ +
`Get-DlpComplianceRule` ✓ (Copilot DLP), `Get-DspmPolicy` ✓ (collection policies),
`Get-AppRetentionCompliancePolicy` ✓ + `Get-RetentionCompliancePolicy` ✓ (AI retention),
`Get-SupervisoryReviewPolicyV2` ✓ + `Get-SupervisoryReviewRule` ✓ (CC Copilot scoping).
No Graph. Cmdlet-level provenance (verified / doc-grounded / unverified) is recorded in
`docs/specs/ai-findings-build-spec.md`.

> Severity policy (spec global rule 3): E5-included AI features → absence is a normal
> Improvement/Recommendation. PAYG / Agent 365 gated surfaces → Informational only, never a gap.
> Every AI sub-read degrades independently: cmdlet-not-found → Informational transparency note;
> access-denied/error → Verify manually.

### AI-01 — AI surface, from S&C evidence
- **Reads:** `Get-DlpCompliancePolicy` ✓ — Copilot-scoped artifacts as the evidence proxy
  (Copilot *deployment* is not detectable read-only from the S&C session and is never asserted).
- **Columns:** Configuration · Setting · Status
- **Status:** artifacts present → **Informational** (AI posture in scope). None → **Informational**
  with a Verify-manually row for deployment ("not detectable read-only", never "absent").
- **Links:** Purview portal — DSPM for AI; Data security for AI.

### AI-02 — Copilot DLP posture (absence / simulation / enforcing)
- **Reads:** `Get-DlpCompliancePolicy` → detection keys in priority order (verified 2026-07-02):
  `EnforcementPlanes` contains `CopilotExperiences`; `Locations` JSON `Workload=Applications` +
  `Location` like `Copilot*` (observed `Copilot.M365`); name match is corroboration **only**.
  One-click default fingerprint (name prefix `Default DLP policy - ` / comment opening /
  `LocationSource=PurviewConfig`, 2 of 3) rendered as an informational tag.
- **Columns:** AI Policy · Conditions (SITs) · Mode · Created · Status
- **Status:** no Copilot-targeting policy → **Recommendation**. Simulation/audit mode
  (`TestWith[out]Notifications`/`Test`/`AuditAndNotify`) → **Improvement** naming the mode
  (one-click default ships as `TestWithoutNotifications` — verified). `Enable` → **OK**.
  `ThirdPartyAppDlpLocation` carriers (⚠ unverified) → factual Informational row when populated,
  silent when empty.
- **Links:** DSPM for AI; DLP for Microsoft 365 Copilot.

### AI-03 — Label-based Copilot content exclusion
- **Reads:** `Get-DlpComplianceRule` (Copilot-location rules) → `ContentContainsSensitiveInformation`
  label groups / `AdvancedRule` JSON — does any rule reference sensitivity labels?
- **Columns:** Configuration · Setting · Status
- **Status:** label-referencing Copilot rule exists → **OK**; none → **Recommendation**.
  Emitted only when Copilot-scoped policies exist to carry the rules.
- **Links:** DLP for Microsoft 365 Copilot; Considerations for Copilot & oversharing.

### AI-04 — DSPM collection policies *(Wave 2; PAYG / Agent 365 gated)*
- **Reads:** `Get-DspmPolicy` ✓ (verified present + Compliance-Reader readable; schema **unknown** —
  0 objects in the sandbox, so the projection is generic name + property/value pairs).
- **Columns:** Collection Policy · Property · Value · Status (dynamic)
- **Status:** ≥1 → **Informational** inventory. 0 → **Informational** with the PAYG/Agent 365
  licensing line — never Improvement/Recommendation (above-E5 rule).
- **Links:** Create and configure retention policies (AI app locations).

### AI-05 — Copilot / AI-app retention coverage *(Wave 2)*
- **Reads:** `Get-AppRetentionCompliancePolicy` ✓ primary — carrier property `Applications` with
  `User:M365Copilot` tokens (**doc-grounded**, not yet observed live); `Get-RetentionCompliancePolicy` ✓
  for the legacy combined `TeamsChatLocation` signal + tenant-wide total.
- **Columns:** Configuration / Policy · Setting · Status
- **Status:** Copilot covered → **OK**. Retention exists but no Copilot coverage → **Improvement**.
  Zero retention tenant-wide → **Recommendation** (sparse-tenant regression case). `Applications`
  absent/odd-shaped → **Verify manually** ("coverage not assertable from cmdlet output") with a
  plain inventory. Legacy TeamsChat policies → transparency row, no coverage assertion.
  Enterprise/Other AI app tokens → verbatim Informational; none → Informational PAYG row.
- **Links:** Retention cmdlets; Create and configure retention policies.

### AI-06 — Communication Compliance Copilot monitoring *(Wave 2, verified end to end)*
- **Reads:** `Get-SupervisoryReviewPolicyV2` ✓ (inventory) + `Get-SupervisoryReviewRule` ✓ —
  scoping lives on the **rule's** `ContentSources` JSON (`Workloads` contains `Copilot`); the
  policy-level `Locations` property is empty even for Copilot-scoped policies (verified).
  Rule→policy via the rule's policy reference, else Name equality (the template pair shares
  "Microsoft 365 Copilot interactions").
- **Columns:** CC Policy / Configuration · Enabled / Setting · Workloads · Status
- **Status:** no Copilot-scoped policy → **Recommendation** (the 'Detect Microsoft 365 Copilot
  interactions' template is the one-step baseline). Scoped + enabled → **OK**; disabled →
  **Improvement**. `UnifiedGenAIWorkloads` / `ThirdPartyWorkloads` non-null → factual
  Informational rows (PAYG-gated channels); null → silent. Access-denied → Verify manually naming
  the CC role-group requirement. Carries the one-line IRM-03 cross-reference (spec rule 7).
- **Links:** Communication Compliance for generative AI.

---

## Open items to resolve during the Code build

1. **Device onboarding count** (DLP-03) — find a read-only source or downgrade to Verify.
2. **License detection** — settle one mechanism (Graph `Get-MgSubscribedSku` vs. cmdlet-availability probing)
   used consistently for every E5 gate (IRM, CC, Audit Premium, eDiscovery Premium, Copilot).
3. **SKU-to-SIT mapping** (DLP-04) — confirm which HIPAA named-entity detectors are inactive sub-E5.
4. **Copilot service-plan id** (AI-01) — confirm the exact plan string.
5. **Learn-more URLs** — the Sensitivity Labels links are verified; validate the rest before shipping.
6. **Read-only guard** — add a repo test asserting no mutating cmdlets appear in collector code.
