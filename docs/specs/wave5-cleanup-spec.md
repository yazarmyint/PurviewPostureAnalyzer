# Build Spec - Cleanup Wave (follows Wave 4)

Repo: yazarmyint/PurviewPostureAnalyzer
Branch: camp-v2-report-first
Status: signed off in planning; ready to build.

## Audience and how to use this spec

This is written for the Code (executor) session and is self-contained; do not
assume access to the planning conversation. Execute one Part at a time. Each
Part ends in a HARD STOP: build and tests are done on DEV, the maintainer
reviews (and validates live items on the TEST machine) before the next Part
begins. Do not start Part N+1 until Part N is approved.

The six cleanup items are grouped into five Parts by coherent concern so each
hard stop reviews one conceptual change:

- Part 1 - Coverage-matrix cell provenance (items 1 and 2)
- Part 2 - Auto-labeling AdvancedRule condition parsing (item 3)
- Part 3 - Sensitivity-label scope name mapping (item 4)
- Part 4 - Remove the HIPAA DLP check (item 5)
- Part 5 - Section reordering across body, Solutions Summary, coverage matrix (item 6)

Parts are ordered correctness-before-cosmetics with no forward dependencies:
nothing in a later Part forces a change to an earlier one.

## Global constraints (apply to every Part)

- Read-only always. Get-* cmdlets only, no mutating cmdlets ever. The existing
  Pester mutation-guard test must stay green.
- PowerShell 5.1, ASCII-only source. None of these items touch delta mode, so
  all new/changed code in this wave is 5.1 / ASCII (the PS 7.5+ delta-mode
  exception does not apply here).
- Layering: collectors in Private/Collect, analyzers in Private/Analyze, render
  in Private/Render. Checks are keyed by stable IDs in CHECK_CATALOG.md.
- Tests: Pester 5, pinned assertions, red-then-green. Write/adjust the failing
  test first, then make it pass.
- Do not fabricate check IDs or file paths. Where this spec refers to a check by
  its behavior, locate the corresponding stable ID in CHECK_CATALOG.md. Where it
  refers to a module by layer, locate the specific file in that folder.
- Preserve existing section and check titles verbatim. This wave reorders,
  parses, maps, and removes; it does not rename anything.

## Validation model

- DEV loop (every Part): fixtures + tools/Build-SampleReports.ps1, then open the
  rendered sample HTML in a browser and eyeball the changed surface.
- TEST loop (live items only): the maintainer opens the report on the TEST
  machine against the live sandbox tenant and confirms against real config.
  Files cannot move between DEV and TEST - only git and pasteable text.
- Live-validatable Parts: 1, 2 (item 3's blob is a DEV fixture; TEST confirms
  the live shape). Parts 3, 4, 5 are display/removal/reorder and are fully
  validatable on DEV via sample reports; no live-tenant dependency.

---

## Part 1 - Coverage-matrix cell provenance (items 1 and 2)

These two items share the cell-provenance model, so they ship as one pass and
one review.

### Goal

1. Un-hold the Copilot x Retention coverage-matrix cell using the confirmed
   app-retention Applications token for Copilot: `Users:M365Copilot`.
2. Flip the auto-labeling and classic-retention matrix cells from
   documented-only (provisional marker) to live-verified.

### Layer and files

- Coverage-matrix collector/analyzer that determines each cell's state
  (Private/Collect and/or Private/Analyze).
- Coverage-matrix render module (Private/Render), including the legend/footnote.
- Follow docs/testday-activation.md for the exact un-hold mechanics on the
  Copilot x Retention cell.

### Contract

- Copilot x Retention: detect Copilot retention coverage by the presence of the
  `Users:M365Copilot` Applications token; render the cell live (covered / not
  covered as appropriate) instead of the on-hold placeholder.
- Auto-labeling and classic-retention cells: render in the clean live-verified
  state; drop the provisional marker on these specific cells. The location
  property shapes these cells depend on are confirmed live, so the provisional
  qualifier is no longer warranted.

### Invariant (the trap to get right)

The provisional-marker legend/footnote renders **if and only if at least one
cell is still in the documented-only state**. After flipping the two cells
above, if no documented-only cells remain, remove the legend/footnote too - do
not leave a legend explaining a marker that no longer appears. If other
documented-only cells still exist, keep it.

### Tests (red then green)

- Copilot x Retention cell reflects coverage when a fixture policy carries the
  `Users:M365Copilot` token, and reflects not-covered when it does not.
- Auto-labeling and classic-retention cells render as live-verified (no
  provisional marker) given the confirmed-shape fixtures.
- Legend invariant: assert the legend is present when a fixture leaves >=1
  documented-only cell, and absent when the fixture set leaves none.

### DEV validation

Build sample reports and confirm in the browser: the three cells render in their
new states and the legend appears/disappears per the invariant.

### TEST validation (live)

On TEST against the sandbox (where real Copilot retention, auto-labeling, and
classic retention policies exist): confirm the Copilot x Retention cell now
reflects the real configuration, and that auto-labeling / classic-retention read
live-verified.

### HARD STOP - review before Part 2.

---

## Part 2 - Auto-labeling AdvancedRule condition parsing (item 3)

The substantive item. Auto-labeling policies that use grouped conditions do not
populate the flat `ContentContainsSensitiveInformation` property; the SITs live
in an `AdvancedRule` property as a JSON string. The tool reads only the flat
property today, so grouped policies render conditions as empty - the misleading
failure mode.

### Goal

When conditions are grouped, parse the `AdvancedRule` JSON and surface a FLAT,
deduplicated list of detected item names plus a total count. Capture both named
SITs and trainable classifiers. Discard the AND/OR group structure - present the
set of things detected, not the boolean logic.

### Fixture (maintainer-provided)

The maintainer will paste a real captured `AdvancedRule` blob (12 sensitive info
types across 4 groups, mixing named SITs and trainable classifiers). Commit it
as a DEV fixture. Derive the expected flat name list and count from this blob
and pin them in the tests. Inspect the blob to determine the exact JSON paths
for SIT-name references vs trainable-classifier references, since the schema is
whatever the real blob is.

### Layer and files

- Collector (Private/Collect): ensure the raw `AdvancedRule` string is captured
  alongside the flat property (if it is not already).
- Analyzer (Private/Analyze): parse and flatten into the name list + count.
- Render (Private/Render): the auto-labeling conditions display in the report
  body.

### Contract - four cases, all visually distinct

1. Flat property populated (ungrouped policy): existing behavior, unchanged.
2. Flat empty, AdvancedRule present and parseable (grouped policy): show the flat
   deduplicated name list (SITs + trainable classifiers combined) and the total
   count.
3. Flat empty, AdvancedRule present but missing/malformed: degrade to
   "conditions present, not parsed" (or equivalent). Must be distinct from
   case 4.
4. Flat empty, no AdvancedRule: genuinely none. Must be distinct from case 3.

The current bug collapses case 2 into case 4. The fix must not leave case 3
looking identical to case 4.

- Total count = number of distinct entries in the flat list (post-dedupe).
- Sort the deduped list for deterministic output (stable render, no
  ordering-based diff noise).

### Snapshot note

If auto-labeling conditions feed the JSON snapshot, store the derived,
sorted name set (stable across tool versions for the same tenant), not
presentation strings. A delta between a pre-fix snapshot (buggy/empty) and a
post-fix snapshot (correctly populated) is a legitimate correction, not spurious
churn - expected and acceptable.

### Tests (red then green), one fixture per case

- Grouped blob fixture -> exact expected name set and count (pinned from the
  real blob).
- Malformed/missing AdvancedRule with empty flat -> "conditions present, not
  parsed" state.
- Empty flat, no AdvancedRule -> none state.
- Populated flat property -> unchanged existing behavior.
- Trainable classifiers from the grouped blob appear in the flat list (not
  silently dropped).

### DEV validation

Build sample reports for each of the four fixtures; confirm in the browser that
all three states are visibly different and the grouped case lists the expected
names and count.

### TEST validation (live)

On TEST, open the report against the sandbox auto-labeling policy that uses
grouped conditions; confirm the live-rendered flat list and count match what the
policy actually detects.

### HARD STOP - review before Part 3.

---

## Part 3 - Sensitivity-label scope name mapping (item 4)

Sensitivity-label scope renders the raw internal value `Teamwork` where it should
read `Teams`.

### Goal

Map internal canonical scope/location values to friendly names at the render
layer, seeded with `Teamwork -> Teams`.

### Layer and files

- Render only (Private/Render), sensitivity-label rendering.

### Contract - render-only mapping table (load-bearing)

- Implement a small internal->friendly mapping table, not a one-off substitution,
  so other leaked internal names can be added uniformly later.
- Seed with `Teamwork -> Teams`. Add entries only for internal values actually
  observed in this report's rendered output today (grep fixtures / sample output
  for known-internal tokens and map the ones that actually appear). Do NOT
  pre-populate a speculative exhaustive list.
- Apply the mapping at the render layer ONLY. Collectors and snapshots keep raw
  canonical values. This is required for delta mode: mapping in the collector
  would make old raw snapshots diff against new friendly ones and show a pure
  display change as a data change.

### Tests (red then green)

- Rendered HTML shows `Teams` for a fixture whose scope is `Teamwork`.
- Delta-safety guard: assert the JSON snapshot for the same fixture still
  contains the raw `Teamwork` value (mapping did not leak into collected/snapshot
  data).

### DEV validation

Build sample reports; confirm the scope reads `Teams` in the browser while the
snapshot retains `Teamwork`.

### HARD STOP - review before Part 4.

---

## Part 4 - Remove the HIPAA DLP check (item 5)

Remove the DLP item "No HIPAA-template policies detected" with nothing in its
place. It presumes a healthcare engagement; the DLP section already surfaces
every industry-neutral hygiene signal a replacement would provide (enforcement
vs. simulation via per-policy remarks + OK/Improvement status; workload coverage
via per-policy remarks and the in-scope section; endpoint posture via the
Endpoint DLP section). No replacement.

### Goal

Delete the check cleanly: its emission, any dedicated collector/analyzer logic,
its tests, and any render reference. The DLP section itself stays; only this line
item goes.

### Layer and files

- Locate the check emitting "No HIPAA-template policies detected" and its stable
  ID in CHECK_CATALOG.md.
- Remove its analyzer/emission logic (and any HIPAA-only collector logic if it is
  not shared).
- Confirm DLP section rendering still works with the line removed.

### CHECK_CATALOG.md handling (surface at the hard stop if unclear)

Check whether the catalog already has a convention for retired/tombstoned checks.
If yes, follow it. If there is no precedent, do NOT hard-delete silently - prefer
tombstoning the ID as retired (stable IDs are meant to stay stable; hard-deleting
risks future reuse/collision) and flag the choice at the hard stop for the
maintainer to confirm.

### Delta note (do not solve)

A pre-wave snapshot that captured this check's result will show it as
"disappeared" when compared to a post-wave snapshot. That is a tool-version
change reading as a config change - acceptable across tool versions. Note it;
do not build anything to suppress it.

### Tests (red then green, inverted)

- Update tests to assert the HIPAA check is ABSENT from emitted checks; they fail
  against current code (which still emits it); removing the check makes them pass.
- Remove or rewrite any test that asserted the check exists.
- Assert the DLP section still renders correctly without it.

### DEV validation

Build sample reports; confirm the DLP section renders and the HIPAA line is gone.

### HARD STOP - review before Part 5.

---

## Part 5 - Section reordering (item 6)

Move DSPM for AI up in the body and the Solutions Summary, and align the
Communication Compliance / Audit / eDiscovery region so the body equals the
flattened summary (Option B, signed off). Reordering is display-only: no check
IDs change and no snapshot content changes, so delta mode is unaffected.

### Target order - report body

1. Sensitivity Labels
2. Data Loss Prevention
3. DSPM for AI - Copilot Data Security
4. Retention and Records
5. Insider Risk Management
6. Communication Compliance
7. Audit
8. eDiscovery

### Target order - Solutions Summary (grouped by solution family)

1. Microsoft Information Protection: Sensitivity Labels, Data Loss Prevention
2. AI Security: DSPM for AI - Copilot Data Security
3. Data Lifecycle & Records: Retention & Records
4. Insider Risk: Insider Risk Management, Communication Compliance
5. Discovery & Response: Audit, eDiscovery

(Keep the "All Solutions" meta-entry wherever it currently sits.) DSPM for AI is
the sole member of the AI Security family, so the whole AI Security group moves as
a unit in the summary; in the flat body, only the single line moves.

### Consistency invariant

Flattening the grouped Solutions Summary must equal the body order exactly.
Flattened summary: Sensitivity Labels, Data Loss Prevention, DSPM for AI,
Retention & Records, Insider Risk Management, Communication Compliance, Audit,
eDiscovery == the body order above.

### Coverage matrix (third place the order may live)

The matrix may carry its own solution-axis order. Locate how the matrix sources
that order and align it to the same canonical sequence. If it orders
independently, that is the third edit that keeps the three views from drifting.

### Single source of truth (preferred) + guardrail (required)

- Preferred, if not too invasive for a cleanup wave: have body, Solutions Summary,
  and coverage matrix all consume ONE canonical ordered list so they cannot drift.
- Required regardless: add a test asserting the three orders are consistent
  (flattened summary == body order, and matrix solution axis == that sequence), so
  future drift is caught even if the orders remain separately defined.

### Titles

Do not rename anything. Note the summary currently reads "Retention & Records"
while the body reads "Retention and Records"; leave both exactly as they render
today. This wave reorders only.

### Tests (red then green)

- Body renders in the target order.
- Solutions Summary renders in the target grouped order.
- Coverage matrix solution axis renders in the target order.
- Consistency guardrail: flattened summary == body order == matrix axis order.
- Delta-safety: snapshot content is unchanged by reordering (no check IDs or
  snapshot fields altered).

### DEV validation

Build sample reports; confirm all three surfaces show DSPM for AI in its new
position and that body and summary now read in the same order end to end.

### HARD STOP - review; wave complete on approval.

---

## Appendix - carried-forward future-wave candidates (NOT this wave)

Logged so they are not lost; explicitly out of scope for cleanup.

- DLP grouped-conditions parsing: the same AdvancedRule-vs-flat-property split
  that item 3 fixes for auto-labeling also affects DLP policies. If the report
  displays DLP conditions, it likely has the same empty-when-grouped bug.
- DLP detect-without-action check: an enforcing DLP policy with SITs but no
  block/notify/restrict action is a real, industry-neutral misconfiguration and
  the one genuinely valuable neutral signal the DLP section is missing. It
  requires reading rule-level actions the collector does not gather today
  (net-new collector + analyzer + check ID + tests + live validation) - a
  feature, not cleanup.

These two pair naturally into a single future "DLP policy internals" wave.
