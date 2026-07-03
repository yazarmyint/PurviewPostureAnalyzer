# Known limitations

What a read-only, session-based analyzer cannot assert with confidence, and how each case is
handled. The guiding rule across all of them: **never overstate assurance.** When a signal cannot
be read safely read-only, the report shows **Verify manually** rather than a fabricated or assumed
value. This file is maintained as the build continues.

---

## DLP-04 - HIPAA / enhanced-template detector tiering

**Limitation.** There is no reliable read-only way to determine which sensitive-information-type
(SIT) detectors are active at a tenant's licensing tier. Several named-entity detectors in the
enhanced HIPAA template (for example ICD-10-CM, ICD-9-CM) require Microsoft 365 E5 / E5 Compliance.

**How it's handled (fail-safe).** A small, dated map — `Data/dlp-sit-tiers.json` — lists only the
**well-known E5-gated** named-entity SITs. Because the tool reads no licensing (decision D9):

- A **mapped** E5-gated SIT -> **Verify manually** ("named-entity SIT - requires E5 - verify tenant
  tier"). The tool never claims the detector is active or inactive on this tenant.
- Any **unmapped** SIT -> **Verify manually** ("tier not confirmed"). It is **never** silently
  marked OK/available.

**Map contents (last reviewed 2026-07-01):**

| SIT | Required license | Category |
|-----|------------------|----------|
| International Classification of Diseases (ICD-10-CM) | E5 | named-entity |
| International Classification of Diseases (ICD-9-CM)  | E5 | named-entity |

**Maintenance.** Microsoft re-tiers SITs over time. Re-verify every entry against current
`learn.microsoft.com` before each release, update `lastReviewed` in the JSON, and expand the list
**conservatively** — an entry that turns out not to be E5-gated would wrongly downgrade a tenant.
The fail-safe (unmapped -> Verify manually) means an incomplete map is safe; an incorrect map is not.

---

## DLP-03 - Endpoint DLP device onboarding count

**Limitation.** The count of devices onboarded to Purview is not available from a read-only
Security & Compliance cmdlet. **Handled:** the "Devices onboarded" row reports **Verify manually**;
the finding's status comes from `EndpointDlpLocation` presence (which is readable).

---

## LABELS-04 / AI-03 - container and site inventory

**Limitation.** Per-container label coverage (e.g. "0 of 143 groups labeled") and per-site
"N of M labeled" Copilot-oversharing coverage have no read-only source over the Security &
Compliance session. **Handled (v1):**
- **LABELS-04**: coverage rows report **Verify manually**; the finding status comes from
  container-scoped label presence (`Get-Label` ContentType), which is readable.
- **AI-03** was reworked to a signal that IS readable: whether any Copilot-location DLP rule uses a
  *Content contains -> Sensitivity labels* condition (label-based Copilot content exclusion - the
  actual oversharing control). Rules found -> OK; none while the AI surface is in scope ->
  Recommendation. **Caveat:** parsing label references out of live rule output
  (`ContentContainsSensitiveInformation` label groups / `AdvancedRule` JSON) is best-effort until
  confirmed against a live tenant; a missed reference would show as a false "None detected"
  Recommendation. A future phase can add real site inventory via Graph/SharePoint.

---

## Audit ingestion / latency (docs-only caveat, not a report finding)

**Limitation.** "Unified audit logging enabled" (readable, AUD-01) is not the same as "ingesting on
time." Ingestion/latency cannot be confirmed from a read-only configuration session. **Handled:**
this is deliberately **not** a finding in the report (client-facing polish) — before relying on
audit coverage, run a targeted audit search (`Search-UnifiedAuditLog` for a recent known event) to
confirm ingestion out-of-band.

---

## Licensing - assumed E5, annotated, never detected (decision D9)

**Limitation.** The tool reads no licensing or directory data at all - Microsoft Graph was removed
entirely (no module, no scopes, no consent prompts). It cannot know the tenant's actual tier.

**How it's handled (assume E5, annotate tier - matches the original CAMP).**
- The report **assumes Microsoft 365 E5** (or equivalent) when judging Purview workloads. E5-gated
  areas (IRM, Communication Compliance, Audit Premium, eDiscovery Premium) report from evidence
  exactly like E3 workloads: data returned -> real findings; genuinely empty -> a normal
  **Improvement/Recommendation**; unreadable -> **Verify manually** (unknown is never asserted as
  empty). There is no "license not confirmed" category.
- `Data/license-requirements.json` is a **dated map** (with `source` + `lastReviewed`) of which tier
  each check's feature requires, verified against the **Microsoft Purview service description**.
  Findings render it as a subtle `Requires: <tier>` tag that **never changes the verdict** - on a
  sub-E5 tenant, read annotated Improvements as licensing decisions first. The README carries the
  pre-requisite note (recommended: E5, or E3 + E5 Compliance).
- **Microsoft 365 Copilot is a separate add-on outside the E5 assumption.** The AI section stays
  evidence-based: Copilot-location DLP artifacts put the AI surface in scope; with none, Copilot
  deployment is *"not detectable from this session"* - never asserted absent.
- DLP-04 says a referenced named-entity SIT *requires E5 - verify tenant tier*; it never claims the
  detector is inactive on this tenant.

**Maintenance.** Same rule as the SIT map: re-verify every entry against the source page before each
release, update `lastReviewed`, and never add tiers the page does not state. Unannotated checks are
E3-baseline per the same page. Guarded by tests: no-Graph guard + no-license-confirmation-language
guard in `Tests/Module.Tests.ps1`.

---

## Insider Risk Management - policy enumeration

**Limitation.** There is no documented read-only cmdlet to enumerate IRM policies. **Handled:** the
IRM collector attempts enumeration defensively. A genuinely empty result is a normal **Improvement**
(assume-E5 model, decision D9); an unreadable inventory is **Verify manually** - unknown is never
asserted as empty.
