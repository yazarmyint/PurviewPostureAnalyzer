# Remediation Guidance Review (Wave 3.1)

> **Every entry is a DRAFT until a human reviews it.** Remediation content is display-only
> text rendered inside Improvement / Recommendation findings; this tool executes nothing.
> Wave 3.1 removed all PowerShell from remediation (B1) - guidance is portal-first prose,
> hard-capped at 3 sentences, naming the key decision, never a bare blade path.

## B2 - Grounding self-audit (the determination record)

Method: enumerated the skill library at `C:\Users\myint\.claude\skills\`, read the ten
skills relevant to the eight check domains, and judged each check honestly: **GROUNDED**
only where a skill, the finding's own Microsoft Learn link, or well-established portal
navigation supports specific guidance *including the key decision*; **NOT GROUNDED**
otherwise - those checks take the B4 fallback (portal path + Learn link, no specifics).

Skills read (2026-07-03): `purview-data-classification`, `purview-dlp-policy`,
`purview-advanced-dlp`, `purview-data-lifecycle`, `purview-records-management`,
`purview-insider-risk-management`, `purview-audit`, `purview-ediscovery`,
`purview-communication-compliance`, `purview-dspm-ai`, `purview-copilot-oversharing`,
`defender-for-endpoint` (device onboarding only).

| Check | Grounded | Source used | Key decision the guidance names |
|---|---|---|---|
| LABELS-01 | **YES** | skill: purview-data-classification | Keep the taxonomy small (<=4 top-level labels, business-language names) with data-owner sign-off - not IT-invented tiers |
| LABELS-02 | **YES** | skill: purview-data-classification | Publishing scope: which users get which labels, plus the default label; verify pilot users see the label menu |
| LABELS-03 | **YES** | skill: purview-data-classification + finding Learn link | Review simulation match counts and a false-positive sample BEFORE enabling - enforce-on-day-one mislabels at scale |
| LABELS-04 | **YES** | skills: purview-copilot-oversharing, purview-data-classification + finding Learn link | Decide what each container label enforces (guest access, external sharing, unmanaged-device limits) with site owners |
| DLP-01 | **YES** | skill: purview-dlp-policy | Review simulation matches in Activity Explorer and define exceptions/overrides BEFORE switching to enforce |
| DLP-02 | **YES** | skill: purview-dlp-policy | Add the Teams location knowing it is NOT retroactive (applies to messages after the change); start with warn |
| DLP-03 | **YES** | skills: purview-dlp-policy, defender-for-endpoint | Device onboarding (Intune / Defender for Endpoint) and per-user licensing come first; start audit-only, never block on day one |
| DLP-04 | **NO** | none sufficient - SKU-to-SIT tier mapping is an open item in this repo's own catalog; no skill covers per-detector E5 gating | B4 fallback (portal path + Learn only) |
| RET-01 | **YES** | skill: purview-data-lifecycle | File plan first: map each retention rule to a policy (breadth) or label (precision) with a named business owner |
| RET-02 | **YES** | skill: purview-data-lifecycle | Build query-based adaptive scopes and preview membership before retargeting policies, so coverage follows the org |
| RET-03 | **YES** | skills: purview-data-lifecycle, purview-records-management | Choose auto-apply conditions (SITs / KQL / classifiers) and simulate first - mis-targeted auto-apply is hard to roll back |
| IRM-01 | **YES** | skill: purview-insider-risk-management | Privacy controls (pseudonymization, role separation, legal/works-council review) BEFORE the first policy; start one template in analytics mode |
| IRM-02 | **YES** | skill: purview-insider-risk-management | HR/Legal alignment plus the HRIS connector - without it the departing-users template has no trigger |
| IRM-03 | **YES** | skill: purview-insider-risk-management | DSPM for AI signals are the upstream prerequisite - the Risky AI usage template has nothing to score without them |
| AUD-01 | **YES** | skill: purview-audit + finding Learn link (verified 2026-07-03) | Needs the Audit Logs role (Exchange Online); allow up to 60 minutes; then set retention for crucial events before an incident needs them |
| AUD-02 | **YES** | skill: purview-audit | Confirm ingestion with a sample search for known-recent activity; audit search has latency - "enabled" is not "ingesting" |
| AUD-03 | **YES** | skill: purview-audit | Match the retention tier to the investigation window (default retention is the most common gap found post-breach) |
| ED-01 | **YES** | skill: purview-ediscovery | Case hygiene: per-case role-scoped access, holds applied before searching, cases closed only when legal confirms |
| ED-02 | **YES** | skill: purview-ediscovery | Which capabilities need E5 / add-on licensing (review sets, analytics, Copilot interaction collection) |
| CC-01 | **YES** | skill: purview-communication-compliance | Pseudonymized, least-privilege reviewers and legal/HR sign-off before rollout; start narrow with a template on the population that needs supervision |
| AI-01 | **YES** | skill: purview-dspm-ai | Tenant-wide Audit is the prerequisite; run the data assessments before turning on enforcement |
| AI-02 | **YES** | skill: purview-dspm-ai | Label maturity gates enforcement - review what the audit-mode policy matched before enforcing (unlabeled content gives it nothing to act on) |
| AI-03 | **YES** | skills: purview-dspm-ai, purview-copilot-oversharing | Decide WHICH labels to exclude from Copilot grounding and verify with a test prompt against labeled content |
| AI-04 | **NO** | none - collection-policy schema/configuration not covered by any skill; surface was unknown even in this repo's Wave 2 probe (0 objects observed) | B4 fallback (portal path + Learn only) |
| AI-05 | **YES** | skill: purview-data-lifecycle + finding Learn link | Decide the retain/delete period for Copilot interactions with the records owner; mind retention precedence with existing policies |
| AI-06 | **YES** | skills: purview-communication-compliance, purview-dspm-ai | Same privacy prerequisites as CC-01; start from the Copilot-interactions template and decide the supervised population |

**Tally: 24 GROUNDED / 2 NOT GROUNDED (DLP-04, AI-04).**

Renders-in-report note: only Improvement/Recommendation findings show the region, so on
the current fixtures DLP-04 (Verify manually), RET-01/AUD-02/AUD-03/ED-01/ED-02/AI-01/AI-04
(Informational/Verify) carry catalog entries that do not render today; they exist so the
structure stays complete if a status flips on another tenant.

## B3/B4 - Drafted guidance (added after the table above was vetted)

*Pending: this section is filled in by B3 (grounded prose, 2-3 sentences naming the key
decision) and B4 (fallback lines) once the determination table is approved. The rendered
text lives in `Data/remediation-catalog.json`; each entry also carries a `grounding`
field (`skill` / `learn` / `established` / `none`) matching this table.*

## Reviewer checklist

- [ ] The grounded/not-grounded determinations above are honest and complete.
- [ ] Each grounded guidance names a real decision, not a blade path.
- [ ] No PowerShell anywhere in remediation content.
- [ ] Fallback entries make no specific claims.
- [ ] Portal menu labels spot-checked against the live portal (they drift).
