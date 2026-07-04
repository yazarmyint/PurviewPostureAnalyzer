# SPEC: Wave 4 - JSON Snapshot, Delta Mode, Coverage Matrix

Repo: yazarmyint/PurviewPostureAnalyzer, branch camp-v2-report-first
Spec status: FINAL - all design decisions ruled. Build to this document.
Session constraint: DEV only, fixtures only. No feature in this spec may
require a live tenant to prove correctness. All validation is Pester +
Build-SampleReports.ps1 visual review.

---

## 0. Scope and non-goals

IN SCOPE
- A. Normalized-model audit (prerequisite pass, small)
- B. JSON snapshot: structured, versioned serialization of normalized
  collector objects + evaluated findings, emitted alongside the HTML report
- C. Delta mode: offline diff of two snapshots into a "what changed" HTML view
- D. Coverage matrix: workload x protection grid rendered near the top of
  the report, projected purely from already-collected data

OUT OF SCOPE (do not build, do not stub)
- Cross-client aggregation of any kind
- Replay mode
- New collector reads / new cmdlets
- New check IDs or severity assignments from the matrix
- Copilot x Retention matrix cell activation (render-hold; see D.6)
- Anything on the deferred-to-TEST list (live Wave 2 validation, legacy EXO
  overlap, collection manifest appendix, IRM depth, departing-employee check)

BUILD ORDER: A -> B -> C -> D. Snapshot schema decisions are the riskiest
to retrofit; matrix is a pure view with no schema gravity.

---

## 1. Runtime matrix (ruled decision)

| Component            | PS 5.1 (Windows PowerShell) | PS 7+ (pwsh) |
|----------------------|------------------------------|--------------|
| Collectors/analyzers/HTML report | required (unchanged repo convention) | should also pass |
| Snapshot WRITER      | REQUIRED - must be fully 5.1-compatible | should also pass |
| Delta mode (loader + differ + delta report) | REFUSED with actionable message | REQUIRED (floor 7.5+, see addendum) |

ADDENDUM (C-fix 1, 2026-07-03): the delta engine floor is PS 7.5+, not 7.0 -
the loader depends on ConvertFrom-Json -DateKind String (added in 7.5) to
keep date-like leaves as verbatim strings. Gate message updated accordingly.

Rationale (recorded for posterity): engagement collection runs may execute
on client-provided jump boxes where installing PS 7 is change-management
friction; the snapshot is written during that run. Delta only ever runs on
consultant machines.

Gates:
- Delta entry point checks engine version via an injectable version-check
  function (so Pester can test the refusal without a real 5.1 host). Refusal
  message must name the requirement and the reason (7.5 floor per C-fix 1):
  "Delta mode requires PowerShell 7.5 or later (run under pwsh). Snapshot
  capture works on Windows PowerShell 5.1; comparing snapshots does not."
- TASK 0 FOR CODE, before anything else: verify both engines are available
  on DEV (powershell.exe 5.1 and pwsh 7+). The Pester suite will be run
  under both: writer tests must pass on 5.1; delta tests run on 7+ only and
  are skipped with an explicit skip reason on 5.1. If pwsh is absent on DEV,
  stop and report - do not proceed with delta work untested.

5.1 writer quirk rules (each gets a pinned test, see section 6):
- ConvertTo-Json with explicit -Depth 16 always. 5.1 truncates SILENTLY at
  depth; a depth-canary object in fixtures round-trips to prove no loss.
- Enums serialize as integers on 5.1. Therefore the normalizer contract is
  extended: every leaf value in a normalized object must be string, number,
  boolean, or null. Enums and any non-primitive leaves are stringified at
  normalize time. A Pester test walks all normalized fixture objects and
  fails on any non-primitive leaf.
- DateTimes are already ISO-8601 UTC strings at normalize time (existing
  rule; re-pin it).
- Non-ASCII escapes to \uXXXX on 5.1: acceptable, no action.
- Single-element array collapse is a ConvertFrom-Json (loader) problem; the
  loader is PS 7-only and coerces declared array fields (see 3.4).

---

## 2. Part A - Normalized-model audit (prerequisite)

Small pass over Private/Collect + Private/Analyze normalized outputs before
snapshot work begins:

A.1 Confirm every normalized object type has, or can be given, a stable
    identity per the keying rule (Guid -> Identity -> Name). Produce a short
    table (type -> chosen key source) committed as docs/KEY_SOURCES.md.
A.2 Enforce the primitive-leaf rule (section 1). Fix any offenders at the
    normalizer, never at the writer.
A.3 Strip session artifacts (RunspaceId, PSComputerName, PSShowComputerName,
    PSSourceJobInstanceId and similar) at normalize time if any survive.
A.4 Confirm the per-collector outcome enum is emitted for every collector:
    Populated | Empty | Partial | AccessDenied | CmdletUnavailable | Failed
    | Skipped | NotRun. Extend any collector that does not yet report one.

Output of Part A: KEY_SOURCES.md + normalizer fixes + green tests. No
schema files yet.

---

## 3. Part B - JSON snapshot

### 3.1 Emission
- Written during a normal report run, alongside the HTML, unless suppressed.
  Parameter: -NoSnapshot to suppress; default is emit.
- File name: PPA-Snapshot_<tenantIdShort>_<capturedAtCompact>Z_<snapshotId8>.json
  where capturedAtCompact = yyyyMMddTHHmmss (UTC), snapshotId8 = first 8
  chars of the snapshot GUID. Example:
  PPA-Snapshot_a1b2c3d4_20260703T141500Z_9f8e7d6c.json
- Snapshots are ALWAYS UNREDACTED in v1 (ruled). They contain UPNs and scope
  identities and are engagement-confidential; the redacted HTML report is
  the artifact that travels. Emit this as a one-line notice to the console
  when a snapshot is written.
- -IncludeRawCapture writes raw collector output to a SEPARATE debug file
  (PPA-RawCapture_...json) outside the schema. Never referenced by delta.

### 3.2 Schema (v1.0)
Top level:
```
{
  "schemaVersion": { "major": 1, "minor": 0 },
  "toolVersion": "<module version string>",
  "snapshotId": "<guid>",
  "capturedAt": "<ISO-8601 UTC>",
  "tenantId": "<from existing IPPS session identity - no new reads>",
  "profile": "<profile name or null>",
  "sectionsRun": [ "<section id>", ... ],
  "redactionState": "none",
  "denylistVersion": "<string, e.g. 1.0>",
  "environment": {
    "psEdition": "...", "psVersion": "...",
    "modules": { "<name>": "<version>", ... }
  },
  "collectorOutcomes": { "<collectorId>": "<outcome enum string>", ... },
  "objects": { "<typeName>": [ <normalized object>, ... ], ... },
  "findings": [ <finding record>, ... ]
}
```
- Two layers only (ruled): normalized objects + evaluated findings. No raw.
- Finding record: { checkId, status, severity, section, title } - enough
  for FindingChanged classification; details live in the HTML.

### 3.3 Identity stamping (writer side)
- Keying rule: Guid if present -> Identity -> Name. Each serialized object
  carries "_key" and "_keySource" ("Guid"|"Identity"|"Name"), stamped at
  capture. Keys are namespaced per type (uniqueness enforced within a type
  array, not globally).
- Duplicate key within a type: writer disambiguates deterministically
  (append #2, #3 in stable input order) and emits a console warning naming
  the type and colliding key. Pinned test.

ADDENDUM (A.5 review, 2026-07-03) - opaque identity contract: guid and
_key values are opaque strings end-to-end. The writer stamps them as-is;
no GUID format parsing or validation exists anywhere in writer, loader,
or differ. (Format normalization - all-zeros Guid, DateTime.MinValue -
lives at the normalizer only.) Fixture guid slugs (guid-<name-slug>) are
therefore first-class test inputs. Pinned test lands in Part C.

### 3.4 Loader (PS 7 side, used by delta only)
- ConvertFrom-Json; coerce every declared array field to array (schema
  carries a declared-arrays manifest per type, maintained as a data file in
  Private/, reviewed like the provenance registry).
- Loader validates: schemaVersion present, major supported, required
  top-level fields present. Fail with actionable message otherwise.

### 3.5 Versioning (ruled)
- Same major: compare. Newer-minor snapshot read tolerantly - unknown
  fields ignored with a single summary warning.
- Different major: refuse: "Snapshot A is schema vX, this tool compares
  schema vY. Re-run the newer tool against the tenant to produce a
  comparable snapshot." No migration shims until a real major bump exists.

### 3.6 Noise handling (ruled)
- Session artifacts: stripped at normalize (Part A.3) - never in snapshots.
- Posture denylist: applied at COMPARE time using the CURRENT tool's list.
  Global core: WhenChanged, WhenCreated, WhenChangedUTC, WhenCreatedUTC,
  ObjectVersion, DistinguishedName, ExchangeObjectId, Guid-churn artifacts
  identified during build; plus per-type extensions. Maintained as a
  reviewed data file with its own version string.
- denylistVersion is recorded in snapshot metadata as INFORMATION ONLY (the
  compare uses the current list). If the two snapshots record different
  denylist versions, the delta report shows an informational note.
- A change ONLY in denylisted properties classifies as Unchanged.
- Per-type extension candidates (decide when the denylist file exists):
  DspmPolicy props-bag entry n='Guid' (the generic property bag duplicates
  the top-level identity field; diffing it would double-report identity).

---

## 4. Part C - Delta mode

### 4.1 Invocation (ruled: fully offline)
- Invoke-PurviewPostureAnalyzer -DeltaFrom <a.json> -DeltaTo <b.json>
  [-OutputPath ...] [-Redact] [-RedactNames] [-AllowTenantMismatch]
- No tenant session is created or required. File-in, HTML-out. PS 7+ only
  (section 1 gate).

### 4.2 Pre-compare validation
- Tenant mismatch (tenantId differs): REFUSE by default; proceed only with
  -AllowTenantMismatch. If either tenantId is absent: warn, proceed.
- capturedAt order reversed (From newer than To): warn, DO NOT auto-swap.
- Schema gates per 3.5.

### 4.3 Compare semantics
- Sections: a section is compared iff present in BOTH snapshots'
  sectionsRun. Otherwise it is NotCompared with a reason string naming
  which side lacked it. NEVER mass Added/Removed from section absence.
- Visibility precedence: for a compared section, if EITHER side's governing
  collector outcome is not in { Populated, Empty }, object-level diff for
  that section is suppressed and replaced by a single VisibilityChanged
  record stating both outcomes (e.g. "AccessDenied -> Populated: 3 policies
  now observable"). Empty -> Populated IS a real Added (both readable).
- Join: objects joined on _key within type; then a GUID-equality
  reconciliation pass catches rename-with-same-Guid (classified Modified
  with a rename annotation), so renames never appear as Removed+Added.
  ADDENDUM (A.5 review, 2026-07-03): "GUID-equality" is defined as
  NON-EMPTY STRING EQUALITY on the guid field - opaque comparison, no
  format parsing or validation (see 3.3 addendum). Pinned test in Part C.
- Property comparison: denylist-filtered (current list); declared array
  fields compared order-insensitively; all other values compared as
  primitives (guaranteed by the normalizer contract).

### 4.4 Change taxonomy (ruled)
- Added, Removed, Modified (property-level old -> new),
  FindingChanged (checkId with status and/or severity old -> new),
  VisibilityChanged, NotCompared (with reason), UnchangedCount.
- Significant-property registry (reviewed data file): properties whose
  change is PROMOTED in the report (e.g. DLP policy Mode sim -> enforce,
  Enabled flips, Workload/location membership changes). These render in
  the headline tier; other Modified detail renders in the detail tier.
- Identity-failure heuristic: within a compared section, if Added > 0 and
  Removed > 0 and Modified == 0 and UnchangedCount == 0, render a warning
  banner: likely identity/keying failure, review _keySource values.

ADDENDUM (Part A review, 2026-07-03) - carry-forward for the differ: the
normalizer maps null and placeholder values (DateTime.MinValue, all-zeros
Guid) to empty strings, so the differ must treat empty-string and
absent-property consistently (absent == '' for comparison purposes); a
property moving between absent and '' is never a Modified.

### 4.5 Delta report render
- Reuses the existing render boundary: HTML-encoding unconditional;
  redaction (stable pseudonyms) applied at render iff -Redact/-RedactNames.
  Snapshots stay unredacted; redaction is a render-time concern (ruled).
- Header: both snapshotIds, tenantId, both capturedAt values, and the span
  ("41 days"). Per-section blocks: headline changes, detail changes,
  VisibilityChanged / NotCompared notices, and ALWAYS the per-section
  unchanged count (confidence signal).
- Print stylesheet + anchors reuse Wave 3 patterns.

---

## 5. Part D - Coverage matrix

### 5.1 Placement and framing
- Rendered near the top of the report, after the Wave 3 Posture Summary.
- Footer line (verbatim intent, wording may be polished): "Assessed via
  Security & Compliance PowerShell only. Container labeling for SharePoint
  and Teams is out of scope for this matrix."
- Degraded-collector banner above the matrix whenever any governing
  collector outcome is outside { Populated, Empty }.

### 5.2 Grid shape (ruled)
- Rows (workloads): Exchange Online, SharePoint, OneDrive, Teams,
  Endpoint, Power BI, Copilot.
- Columns (location-scoped controls ONLY): DLP, Auto-labeling, Retention.
  The Auto-labeling column is explicitly titled "Auto-labeling" - it is
  grounded in auto-sensitivity-label policy locations, NOT label publishing.
- Tenant-level strip below the grid: Audit (unified audit on/off) rendered
  once, never per-row.
  ADDENDUM (Part A review, 2026-07-03): the audit strip grounds on presence
  of the AuditConfig singleton (unifiedAuditEnabled successfully read), NOT
  on the audit collector outcome, so a Partial caused by a secondary read
  failure (Get-OrganizationConfig) does not render the strip Unknown when
  the answer is known. Final wording decided at Part D.
- Principal-scoped strip: Label publishing, Insider Risk, Communication
  Compliance - present/absent summaries with counts, no workload cells,
  one line each linking to their sections.
- Static applicability table (reviewed data file) drives N/A cells (e.g.
  Endpoint x Retention, Power BI x Auto-labeling if not applicable, etc. -
  Code derives the table from cmdlet location properties actually present
  in the normalized model and flags any judgment calls in the PR notes).

### 5.3 Cell states (ruled: closed enum, qualifiers are attributes)
- Covered | Partial | Test-only | None | Unknown | N/A.
- Partial carries MANDATORY reason codes (>=1): ScopedInclude,
  HasExceptions, SubsetOfLocations, AdaptiveScope, RuleDisabled.
- Aggregation across multiple policies touching a cell: best-of precedence
  Covered > Partial > Test-only > None.
- Unknown iff the governing collector outcome is outside
  { Populated, Empty }. Never otherwise.
- Adaptive-scoped policy contributions classify Partial + AdaptiveScope.
- Test-only: the ONLY coverage present is simulation/test mode. Any
  enforcing policy present lifts the cell above Test-only per precedence.

### 5.4 Grounding and provenance (ruled)
- Per-cell provenance registry (reviewed data file in Private/):
  live-verified | documented-only per (row, column) grounding fact.
- DLP column: grounded in VERIFIED per-location properties
  (ExchangeLocation, SharePointLocation, OneDriveLocation, TeamsLocation,
  EndpointDlpLocation, PowerBIDlpLocation + Exception props). Registry:
  live-verified.
- Auto-labeling column: property shape documented-only (NOT on the verified
  list). Cells render with the provisional marker until TEST-day probing.
- Retention column, classic workloads (EXO/SPO/OneDrive/Teams): grounded in
  Get-RetentionCompliancePolicy location properties - documented-only
  unless already on the verified list; render provisional marker
  accordingly.
- Provisional marker: small corner glyph + tooltip "property shape
  documented but not yet verified on a live tenant." Distinct from Unknown.

### 5.5 None vs Unknown rendering (ruled)
- Distinct color families PLUS hatching PLUS glyph PLUS in-cell text
  (colorblind- and print-safe; the print stylesheet must preserve the
  distinction without color).
- Unknown cells are NEVER counted in any gap/hole total.

### 5.6 Copilot x Retention cell: RENDER-HOLD (ruled)
- The Wave 2 app-retention collector continues to run and its normalized
  objects ARE captured in every snapshot (capture is NOT held). Only the
  matrix cell mapping is withheld.
- The cell renders as an em-dash, outside the state enum (no assertion
  made), excluded from all totals, with a footnote: "Retention assessment
  for Copilot deferred pending live verification of the Applications
  token" linking to the existing Wave 2 Copilot-retention check ID (Code:
  pull the exact ID from CHECK_CATALOG.md; do not invent one).
- TEST-day activation checklist (record in docs/, do not build now):
  (1) probe Applications token shape on live tenant, (2) update provenance
  registry entry to live-verified, (3) add the analyzer cell mapping,
  (4) un-hold the cell, (5) confirm interim snapshots diff cleanly.

### 5.7 Purity (ruled, Pester-pinned)
- The matrix is a pure projection: analyzer builds a CoverageModel from
  already-normalized objects; renderer draws it. It creates NO findings,
  NO reads, NO severities. Cells anchor-link to relevant existing check
  IDs. A Pester test asserts the matrix code paths contain no collector
  calls and emit no finding records; the existing read-only guard test is
  extended to cover the new files.

### 5.8 Redaction
- Cell states/reason codes are redaction-safe. Tooltips or detail popovers
  listing contributing policy names pass through the SAME render boundary
  (HTML-encode unconditional, pseudonymize iff redaction mode).

---

## 6. Fixtures and Pester plan

### 6.1 Fixture work
- Extend the DENSE fixture (Contoso Pharma) so every matrix cell state and
  every Partial reason code is exercised at least once, including an
  adaptive-scoped policy, a sim-mode-only cell (Test-only), an exceptions
  case, and one degraded collector (for Unknown + banner).
- SPARSE fixture: matrix renders all-None/Unknown gracefully (the
  graceful-absence regression case).
- Delta fixture pair: tools/New-DeltaFixturePair.ps1 derives snapshots A
  and B from the dense fixture using an EXPLICIT mutation table (checked in
  as data). Required mutations, one assertion each:
  add a policy; remove a policy; rename-with-same-Guid; mutate a location
  array (order change only -> Unchanged; membership change -> Modified);
  flip sim -> enforce (promoted via significant-property registry);
  degrade one collector on side B (VisibilityChanged); drop one section
  from side B's sectionsRun (NotCompared); change only denylisted props on
  one object (Unchanged); a finding status change (FindingChanged).
  Generated A/B files are checked in; a test regenerates and deep-compares
  against the checked-in pair to prevent drift.

### 6.2 Pinned tests (write these FIRST per item, red -> green)
1. Schema golden file: dense-fixture snapshot matches a checked-in golden
   JSON (byte-stable ordering rules defined by the writer).
2. Round-trip deep-compare: serialize dense fixture -> load -> deep-compare
   vs source. Includes empty arrays, single-item arrays, unicode strings,
   hostile strings (quotes, angle brackets, backslashes), and a
   depth-canary object at the writer's max expected nesting.
3. Primitive-leaf walk over all normalized fixture objects.
4. Key stamping: _key/_keySource correctness per KEY_SOURCES.md; duplicate
   key disambiguation + warning.
5. Visibility precedence in all three directions (degraded->readable,
   readable->degraded, degraded->degraded).
6. sectionsRun semantics (NotCompared, never mass removal).
7. Compare-time denylist suppression (noisy-only change == Unchanged).
8. Version gates: cross-major refusal message; newer-minor tolerant read
   with warning; delta-on-5.1 refusal via injected version check.
9. Tenant mismatch refusal + -AllowTenantMismatch override; reversed
   capturedAt warning without swap.
10. Identity-failure heuristic banner.
11. Matrix purity (no reads, no findings) + read-only guard extension.
12. Matrix cell classification: one assertion per state and per Partial
    reason code against the dense fixture; Unknown excluded from totals;
    Copilot x Retention renders held (em-dash, no state, excluded).
13. Aggregation precedence with multiple policies per cell.
14. Redaction: delta report and matrix tooltips pseudonymized under
    -Redact; unredacted snapshot notice emitted.
- Writer-side tests (1-4) must pass under PS 5.1 AND 7+. Delta tests
  (5-10) run under 7+ only, with explicit skip-with-reason on 5.1.

### 6.3 Visual validation (my eyes, DEV loop)
- Extend tools/Build-SampleReports.ps1 to also emit: dense + sparse reports
  WITH matrix, and a delta report from the fixture pair. I review in the
  browser: matrix legibility (None vs Unknown at a glance, print preview),
  provisional markers, banner, delta headline/detail tiers, unchanged
  counts.

---

## 7. Definition of done
- All Pester green under the runtime matrix in section 1 (report current
  totals; expectation is prior 235 + all new pinned tests).
- Read-only guard passes over all new code.
- ASCII-only source maintained; PS 5.1 compatibility verified for
  everything except delta.
- Build-SampleReports.ps1 emits the three new sample artifacts; no
  rendering regressions in existing sections.
- CHECK_CATALOG.md UNCHANGED (matrix adds no checks). docs/ gains
  KEY_SOURCES.md and the TEST-day activation checklist.
- Console notices implemented: unredacted-snapshot notice, duplicate-key
  warning, denylist-version informational note, identity-failure banner.

## 8. Explicitly deferred (do not start)
- Copilot x Retention cell activation (checklist in 5.6).
- Auto-labeling / classic-retention property-shape live verification
  (provisional markers carry them until TEST access).
- Everything on the standing deferred-to-TEST list.
