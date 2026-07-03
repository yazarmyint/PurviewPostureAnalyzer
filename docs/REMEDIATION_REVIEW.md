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

## B3/B4 - Drafted guidance (table above approved 2026-07-03 before drafting)

The rendered text lives in `Data/remediation-catalog.json`; each entry carries a
`grounding` field (`skill` / `learn` / `established` / `none`) matching the table.
Hard cap honored: no entry exceeds 3 sentences; no PowerShell anywhere.

### Grounded drafts (24)

- **LABELS-01** - "In the Purview portal under Information protection > Sensitivity labels, build a small taxonomy - four or fewer top-level labels with business-language names (for example Public / General / Confidential / Highly Confidential). Get data-owner sign-off on the tiers before publishing; an IT-invented taxonomy with many levels stalls adoption and users default to General."
- **LABELS-02** - "Under Information protection > Label publishing policies, publish the labels to the users who create content, deciding the audience scope and the default label for each group. Verify pilot users see the label menu with the intended default in Word and Outlook before widening the rollout."
- **LABELS-03** - "Under Information protection > Auto-labeling, review the policy's simulation results to confirm the matched items and sensitive info types are what you intend, then turn the policy on. Enabling before reviewing simulation can mislabel content at scale."
- **LABELS-04** - "Container labels are created under Information protection > Sensitivity labels by scoping a label to Groups & sites. The real decision is what each label enforces on a workspace - guest access, external sharing, and unmanaged-device limits - so agree those settings with site owners before publishing."
- **DLP-01** - "Under Data loss prevention > Policies, review each test-mode policy's matches in Activity Explorer and define the exceptions and override justifications the business needs before switching the policy to enforce. Blocking without an exception path produces business escalations within hours."
- **DLP-02** - "Under Data loss prevention > Policies, edit each policy's locations to add Teams chat and channel messages, deciding which policies genuinely need Teams coverage. Teams DLP applies only to messages posted after the change - it is not retroactive - so set expectations and start with warn-level actions."
- **DLP-03** - "Endpoint DLP only works on onboarded devices, so onboard them first (Intune is the preferred path, or Defender for Endpoint) and confirm per-user licensing covers Endpoint DLP. Then add the Devices location to the relevant policies and run audit-only before warn or block - blocking on day one turns users against the agent."
- **RET-01** - "Under Data lifecycle management, anchor the retention inventory to a file plan: map each retention rule to a policy (broad, location-level) or a label (item-level precision), each citing a regulation or a named business owner. Rules that exist in the portal but not in the plan are the ones that fail audit."
- **RET-02** - "Under Data lifecycle management > Adaptive scopes, create query-based scopes on user, group, or site attributes and preview the membership they return before retargeting retention policies to them. Adaptive scopes keep coverage current as the organization changes; static scopes quietly drift."
- **RET-03** - "Under Data lifecycle management > Label policies, add auto-apply rules for the retention labels, choosing the conditions deliberately - sensitive info types, KQL, or trainable classifiers - and run them in simulation first. Mis-targeted auto-apply is hard to roll back at scale, so review simulated coverage before broad rollout."
- **IRM-01** - "Before creating any policy under Insider risk management, configure the privacy controls - pseudonymized usernames, separated admin/analyst/investigator roles, and legal or works-council review where required. Then start with a single template in analytics mode for about two weeks to baseline alert volume; enabling every template on day one buries the team in untriaged alerts."
- **IRM-02** - "Treat this as a scoping conversation, not a configuration task: the departing-users template needs HR/Legal alignment and an HR data connector before it has a trigger to fire on. Settle licensing, privacy controls, and the HR feed first, then scope the policy."
- **IRM-03** - "The Risky AI usage template is created under Insider risk management > Policies, but it scores on DSPM for AI signals - enable that visibility first or the policy has nothing to evaluate. Pair it with the same privacy controls and analytics-mode baseline as any other IRM template."
- **AUD-01** - "In the Audit solution, select 'Start recording user and admin activity'; the account needs the Audit Logs role in Exchange Online and enablement can take up to an hour to apply. Once recording, decide audit retention against your investigation window - default retention is the gap most often discovered after a breach."
- **AUD-02** - "In Audit > New search, run a query for activity you know happened recently and confirm events return - enabled is not the same as ingesting on time. Audit search has latency, so allow for it before concluding events are missing."
- **AUD-03** - "Where the tenant tier includes Audit (Premium), decide retention deliberately: match the retention period to how far back an investigation may need to reach, and add audit retention policies for the crucial events (for example mailbox access) rather than relying on defaults."
- **ED-01** - "Under eDiscovery > Cases, keep case hygiene defensible: assign per-case, role-scoped access rather than broad eDiscovery Manager grants, apply holds before searching, and close cases (releasing holds) only when legal confirms the matter is concluded."
- **ED-02** - "Premium capabilities - review sets, analytics, and Copilot interaction collection - depend on E5 / E5 Compliance / add-on licensing per user. Confirm which features your licensing actually enables before building a workflow that assumes them."
- **CC-01** - "Before creating a policy under Communication compliance, put the privacy guardrails in place: pseudonymized usernames for reviewers, tightly scoped reviewer access, and legal/HR sign-off on what is monitored. Then start narrow - one template scoped to the population that genuinely needs supervision - and expand once triage keeps up."
- **AI-01** - "Activate DSPM for AI from the Purview portal and confirm tenant-wide auditing is on - without it there are no interactions to see. Run the built-in data assessments to scope AI risk before turning on any enforcement."
- **AI-02** - "Under Data loss prevention > Policies, review what the Copilot-scoped policy matched during simulation - whether the sensitive info types and prompt matches are what you intend to act on - then switch it to enforce. Classification maturity gates its value: tune the conditions rather than enforcing a noisy default."
- **AI-03** - "The decision is which sensitivity labels Copilot must not ground on: create or edit a policy on the Microsoft 365 Copilot location with a rule referencing those labels, which requires the labels to be deployed and applied first. Verify with a test prompt that Copilot no longer returns the labeled content."
- **AI-05** - "Under Data lifecycle management > Retention policies, create or extend a policy to include the Microsoft 365 Copilot interactions location, deciding the retain/delete period with the records owner rather than defaulting. Check precedence against existing policies - retention wins over deletion and the longest retention wins - so the outcome is deliberate."
- **AI-06** - "Under Communication compliance > Policies, start from the 'Detect Microsoft 365 Copilot interactions' template and decide which population's AI interactions genuinely need supervision. Apply the same privacy prerequisites as any Communication Compliance policy - pseudonymized reviewers, scoped access, and legal sign-off - before enabling."

### Fallback entries (2, NOT GROUNDED)

- **DLP-04** - "Configure in the Microsoft Purview portal under Data classification > Sensitive info types; see the linked guidance for which detectors apply at your tenant's service plan."
- **AI-04** - "Configure in the Microsoft Purview portal under DSPM for AI; see the linked guidance for collection-policy scoping specific to your environment (pay-as-you-go / Agent 365 billing applies)."

## Reviewer checklist

- [ ] The grounded/not-grounded determinations above are honest and complete.
- [ ] Each grounded guidance names a real decision, not a blade path.
- [ ] No PowerShell anywhere in remediation content.
- [ ] Fallback entries make no specific claims.
- [ ] Portal menu labels spot-checked against the live portal (they drift).
