# The delta report - comparing two posture snapshots

The delta report is an **optional, fully offline companion** to the main posture
report. Every normal report run also writes a JSON *snapshot* of what the tool
observed; the delta report compares two of those snapshots from the **same
client** and shows what actually changed in between. No tenant connection is
made or needed - it is file-in, HTML-out.

It runs on **PowerShell 7.5 or later only** (`pwsh`). Snapshot *capture* works
everywhere the analyzer works, including Windows PowerShell 5.1 on a client
jump box; *comparing* snapshots happens later, on your own machine.

## When to use it

The intended rhythm is **kickoff snapshot vs engagement-close snapshot**:

1. At kickoff, run the analyzer as usual. Keep the `PPA-Snapshot_*.json` written
   next to the HTML report.
2. Work the engagement.
3. At close (or the next quarterly check), run the analyzer again and compare:

```powershell
Invoke-PurviewPostureAnalyzer -DeltaFrom .\PPA-Snapshot_kickoff.json `
                              -DeltaTo   .\PPA-Snapshot_close.json
# optional: -OutputPath <dir>  -Redact  -RedactNames
```

The tool refuses to compare snapshots from different tenants (override with
`-AllowTenantMismatch` only when you know why), and warns - without swapping -
if the "from" snapshot is newer than the "to".

## How to read it

- **Assessment visibility** (one block near the top): anything that could NOT
  be fully compared, stated once. This covers sections a run did not include,
  sections where the collector could not read on one or both sides, and checks
  that exist in only one snapshot (usually a tool version difference). None of
  this is evidence of tenant change - it is about what the assessment could see.
- **Headline changes** per section: policies added or removed, renames
  (matched by object identity, so a rename is never shown as delete-plus-add),
  and changes to properties that alter enforcement - a DLP policy leaving
  simulation for enforce mode, an enabled flag flipping, workload membership
  changing. These are the rows to talk about with the client.
- **Detail changes**: every other property change, for completeness.
- **Unchanged counts**: every compared section states how many objects were
  verified identical. Treat this as the confidence signal - "3 changes, 41
  unchanged" is a very different statement from "3 changes, 0 unchanged".
- **Finding changes**: check statuses that moved between the two runs
  (for example DLP-02 going from Improvement to OK).

Noise is filtered by a reviewed denylist (timestamps and directory-churn
properties never count as change), and array order alone is never a change -
only membership is.

## Snapshot confidentiality

Snapshots are written **unredacted** so that the comparison is faithful. The
console says so on every capture:

> `Snapshot : <path> (contains unredacted UPNs and scope identities; treat as engagement-confidential - the redacted HTML report is the artifact that travels)`

Handle snapshot files like working papers: they stay inside the engagement.
The delta *report* supports the same `-Redact` / `-RedactNames` masking as the
main report when it needs to travel.

## Try it without a tenant

`pwsh -File tools/Build-SampleReports.ps1` renders two fixture-driven delta
samples into `Samples/sample-reports/`: a validation pair that exercises every
edge (degraded collectors, dropped sections, renames) and a clean showcase pair
that reads the way a healthy quarterly comparison should.
