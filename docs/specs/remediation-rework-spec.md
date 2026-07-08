# CAMP v2 — Remediation Rework + Summary Rename (Wave 3.1)

**Audience:** Claude Code, continuing on `camp-v2-report-first`.
**Nature:** Content and copy revision of Wave 3 output. Render-layer and data
file only. Zero collector/analyzer/severity changes, zero new cmdlets executed,
no live tenant. Builds and validates on this machine against fixtures.

This wave revises what Wave 3 shipped in P1 (summary heading) and P7
(remediation snippets). Everything else from Wave 3 stays as-is.

---

## Part A — Rename the summary heading

- Change the page-one summary heading from "Executive Summary" to **"Posture Summary"**
  (plain). Rationale: "Executive Summary" over-claims a finished consulting
  deliverable; this is a posture snapshot feeding consultant judgment.
- Update every place the string appears: the rendered heading, any anchor/id
  or aria-label derived from it, README references, and any test that pins the
  heading text. Do not leave a stale "Executive" anywhere.

---

## Part B — Remediation content rework (the substance)

### The problem being fixed

The Wave 3 remediation catalog shipped three PowerShell cmdlets
(`Set-DlpCompliancePolicy -Mode Enable`, `Set-AutoSensitivityLabelPolicy
-Mode Enable`, `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled
$true`). These are **hollow**: they flip a switch but do not address the real
remediation (what to scope, which sensitive info types, which locations, who
it applies to, whether simulation was reviewed first). For a client-facing
report this is actively misleading — it implies a one-liner fixes a posture
gap that Purview never solves that simply.

### B1 — Strip all PowerShell from remediation

- Remove every `cmdlet` value from `Data/remediation-catalog.json`.
- Remove the cmdlet rendering path from the remediation region: no
  `<pre><code>` cmdlet blocks, no copy-to-clipboard-cmdlet button. (If the
  copy button is trivially reusable for the Learn link, fine, but no cmdlet
  code blocks remain.)
- The read-only guard and phrase guards should now have *less* to scan, not
  more — confirm no test depended on a cmdlet block being present.
- The "How to remediate" region itself STAYS on every Improvement /
  Recommendation finding. Only the PowerShell goes.

### B2 — Self-audit gate before writing any guidance (REQUIRED FIRST STEP)

The user has Purview-related skills available in this environment. Before
rewriting remediation content:

1. Enumerate the available skills and read those relevant to Purview
   remediation (DLP, sensitivity/auto-labeling, retention, insider risk,
   communication compliance, audit, DSPM for AI, device onboarding).
2. For EACH of the 26 catalog checks, make an honest determination:
   - **GROUNDED** — the skills (or the finding's existing Microsoft Learn
     link, or well-established portal navigation) let you write accurate,
     specific portal guidance including the key decision the admin must make.
   - **NOT GROUNDED** — you cannot write specific guidance you're confident
     is correct without guessing portal paths, blade names, or prerequisites.
3. Produce this determination as a table in `docs/REMEDIATION_REVIEW.md`
   (rewrite the file): check ID, grounded yes/no, source used (skill name /
   Learn / established navigation), and the drafted guidance. This is the
   auditable record of why each remediation says what it says.

**Do not write confident prose from general recall.** If grounding is thin,
that check takes the B4 fallback. A hollow cmdlet replaced by a confident-but-
wrong paragraph is a worse outcome, not a better one — prose errors are harder
for the user to catch than a bad cmdlet.

### B3 — Depth-capped portal guidance (the GROUNDED path)

For grounded checks, write remediation as portal-first guidance, **2–3
sentences maximum**, structured as: the portal path, plus the key decision or
prerequisite that actually solves the problem (not just where the toggle is).

The failure mode to avoid is elementary path-only guidance that leaves a
non-expert client asking "…okay, and?". Contrast:

- TOO HOLLOW: "Portal: Purview > Information protection > Auto-labeling >
  select the simulation policy > Turn on policy."
- RIGHT DEPTH: "In the Purview portal under Information protection >
  Auto-labeling, review the policy's simulation results to confirm the
  matched items and sensitive info types are what you intend, then turn the
  policy on. Enabling before reviewing simulation can mislabel content at
  scale."

The second still fits 2–3 sentences but names the *decision* (review
simulation before enabling) that makes it real remediation. Every grounded
entry should carry that kind of substance: the SITs/scope/location/audience
decision relevant to that specific check, not generic navigation.

Hard cap: 3 sentences. No numbered step lists, no walls of text. If a check
genuinely needs more than 3 sentences to remediate responsibly, that is a
signal it needs consultant scoping — say exactly that in ≤2 sentences and
point to the Learn link, rather than overloading the report.

### B4 — Fallback (the NOT-GROUNDED path)

When a check isn't confidently groundable: render **portal path + Learn link
only**, minimal and honest. A short generic line is acceptable here (e.g.
"Configure in the Microsoft Purview portal; see the linked guidance for
scoping specific to your environment."). No invented blade names, no guessed
prerequisites, no PowerShell.

### B5 — Catalog + render notes

- `Data/remediation-catalog.json`: each entry now carries `portalPath`
  (string, may be the richer 2–3 sentence guidance), `learnUrl`, and an
  internal `grounding` field (skill/Learn/established/none) for the review
  doc — the `grounding` field need not render in the report but must exist
  for auditability.
- Rendering unchanged structurally: native `<details>` "How to remediate" on
  Improvement/Recommendation findings only, now containing prose guidance +
  Learn link, no cmdlet block.
- Redaction: policy/label names inside the new guidance text must still
  pseudonymize under `-RedactNames`. Re-verify against the redacted sample.

---

## Testing / validation

- Existing Wave 3 suite stays green; update only the assertions that pinned
  "Executive Summary" text or the presence of a cmdlet code block. Any such
  change is explicit in its commit message, never silent.
- Add/adjust tests: remediation region contains NO PowerShell (assert no
  `Set-` / `Connect-IPPSSession` / `<pre><code>` cmdlet markers in rendered
  remediation regions across all fixtures); remediation still renders on
  Improvement/Recommendation; `grounding` present for every catalog entry.
- Regenerate all five sample reports via `tools/Build-SampleReports.ps1`.
- The user reviews `docs/REMEDIATION_REVIEW.md` (the grounded/not-grounded
  table) and the rendered `sample-dense.html` remediation regions as the
  editorial gate before push.

## Build order

1. Part A — summary rename (+ test/README updates).
2. B1 — strip PowerShell from catalog + render + tests.
3. B2 — skills audit, produce the grounded/not-grounded determination table
   in docs/REMEDIATION_REVIEW.md. Pause-worthy checkpoint: the table is the
   thing the user vets.
4. B3/B4 — write grounded guidance / apply fallbacks per the table.
5. Regenerate samples, full suite green, summarize, stop. No push.

## Out of scope

- No collector/analyzer/severity edits. No new executed cmdlets. No Graph.
- Coverage matrix / snapshot / delta remain deferred.
- Do not re-add PowerShell to remediation under any framing.
