# CAMP v2 — AI Findings Build Spec (Wave 2)

**Audience:** Claude Code, implementing against the `camp-v2-report-first` branch.
**Provenance:** Property names and behaviors below were verified against a live
sandbox tenant via SCC PowerShell on 2026-07-02, supplemented by Microsoft Learn
documentation. Facts marked **[VERIFIED]** were observed in live cmdlet output
and override any assumption from training data or docs. Facts marked
**[DOC-GROUNDED]** come from current Microsoft Learn and were not yet observable
in the sandbox. Facts marked **[UNVERIFIED]** are defensive guesses — code
against them null-safely and never assert them in report copy.

---

## Global rules (apply to every finding below)

1. **Read-only, SCC session only.** Every collector call is a `Get-*` cmdlet
   over the existing Security & Compliance connection. Never call
   `New/Set/Remove-DspmPolicy` or any other mutating cmdlet. No Microsoft Graph.
2. **Honest degradation.** Every collector distinguishes four outcomes and the
   report renders each honestly:
   - `CMDLET-NOT-FOUND` → transparency note ("surface not exposed to this
     session / tenant"), no severity.
   - `ACCESS-DENIED` → transparency note naming the missing role, no severity.
   - `EMPTY` (readable, zero objects) → a real finding per the severity policy.
   - `OK` → full finding.
3. **Severity policy — the licensing rule.** CAMP assumes E5 (per README).
   - Features included at E5 (Copilot-experiences DLP, Copilot retention
     location, CC Copilot template, IRM risky-AI template): **absence is a
     legitimate Improvement or Recommendation**, matching original CAMP
     semantics.
   - Features gated above E5 by pay-as-you-go billing or Agent 365
     (Enterprise AI apps location, Other AI apps location, DSPM collection
     policies, CC third-party/unified-GenAI channels): **presence is reported
     factually (OK/Informational); absence is Informational with a one-line
     licensing note.** Never render above-E5 absence as Improvement or
     Recommendation — CAMP does not ding clients for unpurchased SKUs.
4. **JSON-string properties.** Several key properties are JSON serialized into
   strings (`Locations` on DLP policies, `ContentSources` on CC rules). Parse
   with `ConvertFrom-Json` inside try/catch; on parse failure, fall back to
   regex containment checks on the raw string and note reduced confidence.
5. **Null-safe access everywhere.** Schemas drift across tenant rings. Missing
   property ≠ crash; missing property = degrade per rule 2.
6. **State, not just existence.** Every AI finding reports the policy's
   Mode/Enabled state, because one-click defaults ship in simulation
   ([VERIFIED]: the one-click Copilot DLP policy arrived as
   `Mode = TestWithoutNotifications`).
7. **Report placement.** Findings F1–F4 render in the DSPM for AI / Copilot
   Data Security section. F5 renders in the Insider Risk section with a
   one-line cross-reference from the DSPM section. Follow existing section
   conventions (colored callouts, collapsible drill-down tables, Learn-more
   links).

---

## F1 — DSPM collection policies (`Get-DspmPolicy`)

**Status of surface:** [VERIFIED] The cmdlet family
`Get/New/Set/Remove-DspmPolicy` exists in the SCC session and `Get-DspmPolicy`
executes successfully with Compliance-Reader-tier roles. It returned 0 objects
in the sandbox, so the **object schema is unknown** — build the collector
schema-defensively.

**Collector:**
- `Get-DspmPolicy` wrapped per global rule 2.
- Because schema is unknown, serialize returned objects generically: capture
  `Name` if present, plus every property name/value pair into the drill-down
  table dynamically (`$obj.PSObject.Properties`), truncating long values.
  Do not bind to specific property names beyond `Name`.
- Ignore `Import-DlpComplianceRuleCollection` entirely — it matched the probe's
  "collection" keyword but is the legacy DLP rule-collection import cmdlet,
  unrelated to DSPM.

**Finding logic:**
- ≥1 object → Informational/OK: "DSPM collection policies configured: N" with
  dynamic inventory drill-down.
- 0 objects → **Informational** (not Improvement — above-E5 rule): "No DSPM
  collection policies detected. Collection policies govern interaction capture
  for Enterprise AI apps and Other AI apps and require pay-as-you-go billing or
  Agent 365 licensing; applicable only if licensed."
- Cross-reference line [DOC-GROUNDED]: collection policies are a prerequisite
  for governing AI apps other than Microsoft 365 Copilot / Copilot Studio.

---

## F2 — Copilot DLP posture (upgrade of the existing finding)

**Detection keys, in priority order:**
1. [VERIFIED] **`EnforcementPlanes`** property containing `CopilotExperiences`
   (observed as the bare value `CopilotExperiences`; match with a null-safe
   stringified `-match 'CopilotExperiences'` to tolerate string vs array).
2. [VERIFIED] **`Locations`** JSON string: entries with
   `"Workload":"Applications"` and `"Location"` like `Copilot*` (observed:
   `"Copilot.M365"`, `"LocationSource":"PurviewConfig"`). Parse per global
   rule 4; report the specific Location strings found (there may be more than
   one Copilot-family value on other tenants — report what is present, do not
   enumerate a fixed list).
3. Name match (`dspm|copilot|AI`) as tertiary corroboration only — names are
   admin-editable; never rely on name alone.

**One-click artifact fingerprint** [VERIFIED], for labeling a policy as the
Microsoft-deployed default in the drill-down (informational tag, not a
severity input):
- Name prefix `Default DLP policy - ` (observed:
  `Default DLP policy - Protect sensitive M365 Copilot interactions`)
- Comment beginning "Prevent data leakage and oversharing by restricting
  Microsoft 365 Copilot..."
- `LocationSource = PurviewConfig` inside the Locations JSON.

**Finding logic:**
- No Copilot-targeting DLP policy → **Improvement/Recommendation** (E5
  feature): "Microsoft 365 Copilot interactions are not governed by any DLP
  policy."
- Copilot-targeting policy exists but `Mode` is `TestWithNotifications` /
  `TestWithoutNotifications` → **Improvement**: "Copilot DLP coverage exists
  but is in simulation mode ([Mode]); interactions are not being enforced.
  Review simulation results and enable when tuned." (This also feeds the
  existing enforce-vs-audit reporting.)
- Copilot-targeting policy in `Enable` mode → OK, with drill-down listing
  policy name, mode, created date, one-click tag if fingerprint matches.
- [UNVERIFIED] `ThirdPartyAppDlpLocation` /
  `ThirdPartyAppDlpLocationException` exist as property names on DLP policy
  objects and are the probable carriers for non-Copilot AI app DLP scoping.
  If populated on any policy, report factually as Informational; if empty,
  stay silent (above-E5 rule). Do not assert their meaning in report copy
  beyond "third-party app DLP locations configured."

---

## F3 — Copilot / AI-app retention coverage (new finding)

**Status of surface:** [VERIFIED] Both `Get-RetentionCompliancePolicy` and
`Get-AppRetentionCompliancePolicy` execute successfully with current roles
(both returned 0 objects in the sandbox — property shape not yet observed
live).

**Detection** [DOC-GROUNDED, Microsoft Learn retention-cmdlets and
create-retention-policies]:
- Primary: `Get-AppRetentionCompliancePolicy` — the modern AI locations
  ("Microsoft Copilot experiences", "Enterprise AI apps", "Other AI apps")
  live in the App retention family. Expected carrier property: `Applications`,
  with values in the pattern `User:M365Copilot` (Copilot experiences). Match
  Copilot coverage via `Applications` values matching `M365Copilot`
  (case-insensitive, null-safe). If `Applications` is absent or shaped
  differently, degrade: render the policy inventory (names, locations-ish
  properties) plus the transparency line "Copilot retention coverage not
  assertable from cmdlet output on this tenant."
- Secondary/legacy: `Get-RetentionCompliancePolicy` — classic policies with
  `TeamsChatLocation` populated may represent the pre-split combined
  "Teams chats and Copilot interactions" location. Report these as
  "legacy combined Teams/Copilot-era retention policy detected" —
  transparency-flavored, no assertion that Copilot is definitively covered.
- [UNVERIFIED] Exact `Applications` tokens for Enterprise AI apps / Other AI
  apps are not documented in what we captured. If values other than Teams/
  Copilot tokens appear, report them verbatim as Informational.

**Finding logic:**
- No Copilot-experiences coverage found in either family →
  **Improvement/Recommendation** (E5 feature): "Copilot interaction data has
  no retention/deletion lifecycle policy."
- Copilot coverage present → OK with drill-down (policy name, retention
  action/duration if readable, Enabled state).
- Enterprise/Other AI app coverage: present → Informational/OK; absent →
  **Informational** with the PAYG/Agent 365 licensing line (above-E5 rule).
- Zero retention policies of any kind tenant-wide → this must render as a
  clean Recommendation, never a crash or blank section (sparse-tenant
  regression case; the sandbox is currently exactly this shape — use it to
  verify rendering).

---

## F4 — Communication Compliance Copilot monitoring (new finding)

**Status of surface:** [VERIFIED] end to end.

**Collector:**
- `Get-SupervisoryReviewPolicyV2` → policy inventory: `Name`, `Enabled`,
  `Mode`, `CreationTimeUtc`, reviewer info if desired. [VERIFIED] the
  policy-level `Locations` property was empty even for a Copilot-scoped
  policy — **do not key scoping off the policy object.**
- `Get-SupervisoryReviewRule` → scoping lives here. [VERIFIED]
  `ContentSources` is a JSON string; observed shape:
  `{"RevieweeName":"AllUsersGroupsOfTenant", ..., "Workloads":["Copilot"],
  "ThirdPartyWorkloads":null, "UnifiedGenAIWorkloads":null, ...}`.
  Copilot monitored ⇔ parsed `Workloads` array contains `Copilot`.
- Associate rule→policy via the rule's policy reference property if present,
  else by matching `Name` ([VERIFIED] the template-created rule and policy
  share the name "Microsoft 365 Copilot interactions").
- Also read `UnifiedGenAIWorkloads` and `ThirdPartyWorkloads` from the same
  JSON: non-null → report factually as Informational (these are the
  PAYG-gated channels); null → silent.

**Finding logic:**
- No CC policies at all, or none whose rule Workloads contains Copilot →
  **Recommendation** (E5 feature): "AI prompts and responses are not monitored
  by Communication Compliance. The 'Detect Microsoft 365 Copilot interactions'
  template provides a one-step baseline."
- Copilot-scoped policy exists → OK if `Enabled`, Improvement if disabled;
  drill-down: policy name, enabled state, workloads parsed from the rule.
- `ACCESS-DENIED` on either cmdlet → transparency note: "Communication
  Compliance objects require membership in a CC role group; not readable with
  the roles used for this run." Also add this to the README least-privilege
  notes (CC section requires a CC role group in addition to Compliance
  Reader).

---

## F5 — Insider Risk: risky-AI template + TenantSetting fix (IRM section)

**Two changes:**

1. **Bug-risk fix (apply to the existing IRM section and queued IRM-depth
   work):** [VERIFIED] `Get-InsiderRiskPolicy` returns a tenant-settings
   pseudo-object — observed `Name = IRM_Tenant_Setting_<guid>`,
   `InsiderRiskScenario = TenantSetting`. **Exclude
   `InsiderRiskScenario -eq 'TenantSetting'` from all policy counts and
   inventories.** A tenant with zero real policies otherwise reports as
   having one.

2. **Risky-AI template detection (new finding):** [VERIFIED] the template
   identifier property is **`InsiderRiskScenario`**. The exact enum value for
   the risky-AI-usage template is [UNVERIFIED] (no such policy existed in the
   sandbox). Detect via case-insensitive `InsiderRiskScenario -match 'AI'`
   with word-boundary care (avoid matching unrelated scenario names),
   corroborated by policy `Name` matching `AI|Copilot|risky`. When first
   observed on a populated tenant, record the exact enum in a code comment
   and tighten the match.

**Finding logic:**
- No policy with an AI scenario → **Recommendation** (E5 feature): "No Insider
  Risk policy based on the Risky AI usage template; prompt-injection and
  protected-material access signals from Copilot are not being scored."
- Present → OK, drill-down: name, scenario value, Workload list, created date.
- IRM cmdlets `ACCESS-DENIED` → existing IRM-section degradation applies
  (IRM role groups are required beyond Compliance Reader).

---

## Learn-more links to wire into findings

- F1/F3 AI locations & prerequisites:
  https://learn.microsoft.com/purview/create-retention-policies
- F3 cmdlet families (older vs newer locations):
  https://learn.microsoft.com/purview/retention-cmdlets
- F4 CC for generative AI:
  https://learn.microsoft.com/purview/communication-compliance-copilot
- F5 IRM policy templates:
  https://learn.microsoft.com/purview/insider-risk-management-policy-templates
- Section framing (Purview for Copilot overall):
  https://learn.microsoft.com/purview/ai-m365-copilot

---

## Verification ledger (for the README and for future maintenance)

| Fact | Status |
|---|---|
| `Get-DspmPolicy` exists, readable, Compliance-Reader-tier | VERIFIED (2026-07-02 sandbox) |
| DspmPolicy object schema | UNKNOWN — collector is schema-defensive |
| DLP `EnforcementPlanes = CopilotExperiences` | VERIFIED |
| DLP `Locations` JSON, `Workload=Applications`, `Location=Copilot.M365` | VERIFIED |
| One-click DLP default ships `TestWithoutNotifications` | VERIFIED |
| `ThirdPartyAppDlpLocation` as third-party AI carrier | UNVERIFIED — report factually only |
| App retention `Applications` = `User:M365Copilot` | DOC-GROUNDED — verify on first populated tenant |
| CC rule `ContentSources.Workloads` contains `Copilot` | VERIFIED |
| CC `UnifiedGenAIWorkloads` / `ThirdPartyWorkloads` fields exist | VERIFIED (null values) |
| IRM `InsiderRiskScenario` is the template identifier | VERIFIED |
| IRM `TenantSetting` pseudo-policy must be excluded | VERIFIED |
| Risky-AI scenario exact enum value | UNVERIFIED — pattern-match, tighten later |

## Out of scope for this wave

- No Microsoft Graph, no license detection, no policy creation or mutation.
- No findings that render above-E5 absence (PAYG / Agent 365 features) as
  Improvement or Recommendation.
- `Import-DlpComplianceRuleCollection` is unrelated legacy tooling — do not use.
