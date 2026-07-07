# Contributing to Purview Posture Analyzer

Thanks for your interest. PPA is an independent, community-maintained project (see `NOTICE`) -
not a Microsoft product. Contributions are welcome by pull request.

## Non-negotiable guardrails

- **Read-only, always.** Collectors and analyzers may call `Get-*` cmdlets (and `Connect-*` to
  open sessions) only. No `Set-/New-/Remove-/Enable-/Disable-/...` against a tenant, ever.
  `Tests/ReadOnlyGuard.Tests.ps1` fails the build if a mutating cmdlet appears anywhere under
  `Private/` or `Public/`.
- **No Microsoft Graph** (design decision D9 in `PLAN.md`). The tool reads no licensing or
  directory data, so there is no Graph module, no scopes, and no consent prompt. A guard test
  in `Tests/Module.Tests.ps1` enforces this.
- **No PowerShell in remediation guidance.** "How to remediate" content is portal-first prose
  plus a Learn link only - a one-line cmdlet misrepresents what remediation actually involves.

## Source conventions

- **ASCII-only source.** Every `*.ps1`, `*.psm1`, and `*.psd1` must be ASCII, for Windows
  PowerShell 5.1 compatibility. HTML output is emitted with HTML entities (`&mdash;`,
  `&middot;`, `&#8627;`) rather than literal non-ASCII, so the generated source stays ASCII too.
- **Both engines.** Code must run on **Windows PowerShell 5.1** and **PowerShell 7+**. The
  delta report is the one 7.5+-only feature and is gated at runtime.
- **Convention-based loading.** `PurviewPostureAnalyzer.psm1` dot-sources every
  `Private/**/*.ps1` then `Public/*.ps1` and exports only the public basenames, so a new file
  is picked up automatically. If you add a standalone script that dot-sources a *subset* of
  Private (e.g. a tool), list new files explicitly there.

## Tests

- **Pester 5.** Shared setup - variables and helper functions - must live in a top-level
  `BeforeAll`. Pester 5 does not share script-scope state across blocks the way v4 did.
- **Pin your assertions.** Prefer exact `Should -Be` over loose matches. Counts and ordering
  are contracts here (there is a golden-file snapshot test, `Tests/Snapshot.Tests.ps1`).
- Run the **full suite on both engines** before proposing a change:

  ```powershell
  # Windows PowerShell 5.1
  powershell.exe -NoProfile -Command "Invoke-Pester -Path .\Tests"
  # PowerShell 7+
  pwsh -NoProfile -Command "Invoke-Pester -Path .\Tests"
  ```

  Then render the samples and confirm they still open:

  ```powershell
  pwsh -File tools/Build-SampleReports.ps1
  ```

## Change flow

- Work on a **branch off the current tip**; do not commit directly to `main`.
- Land changes in **small, reviewable parts**. For anything that **moves or deletes files**,
  treat the full suite (both engines) plus a sample-report build as the gate - advance only on
  green.
- The project uses a **two-machine workflow** (development on one box, validation on another);
  changes move only via git, so keep every commit self-contained and buildable.

## Design anchors

- **`CHECK_CATALOG.md` is the domain spec**: every check ID, the cmdlet and property it reads,
  and the status rule. Add or change a check there first, then in code.
- **Five-status model** - OK / Improvement / Recommendation / Informational / Verify manually.
  E5-tier gaps on a sub-E5 tenant are *annotated*, never downgraded to a fabricated verdict
  (`LIMITATIONS.md`, decision D9). "Unknown" is never asserted as "empty".
- **Report-first.** The finding object is the design center; the HTML report is its primary
  rendering and the JSON export is the same objects serialized.

## Reporting issues

- Bugs and questions: **GitHub Issues** (see `SUPPORT.md`).
- Security vulnerabilities **in the tool**: **private reporting** only (see `SECURITY.md`) -
  do not open a public issue.
