# TEST-day activation checklist (Wave 4 deferrals)

Recorded per spec 5.6 - these items are HELD until a live TEST tenant is
available. Nothing here is built or asserted today.

> **Status update (2026-07-06, Wave 5 cleanup Part 1):** items 1 and 2 are
> DONE. The observed `Applications` token is `Users:M365Copilot` (plural
> `Users:` - the doc-grounded `User:` singular was not the live shape). The
> Copilot x Retention cell is un-held and classifies live; the auto-labeling
> and retention column provenance flipped to `live-verified`, so the
> provisional markers no longer render. Item 1 step 5 (interim snapshot delta)
> holds by construction - snapshots never embedded the coverage model and the
> collector is unchanged - and the delta fixture suite stays green; confirm
> against a real pre/post pair on TEST. Item 3 remains open.

## 1. Copilot x Retention matrix cell (render-hold)

The Wave 2 app-retention collector already runs and its normalized objects are
captured in every snapshot (capture is NOT held). Only the matrix cell mapping
is withheld: the cell renders an em-dash outside the state enum, excluded from
all totals, footnoted to check **AI-05**.

Activation steps, in order:

1. Probe the `Get-AppRetentionCompliancePolicy` `Applications` token shape on a
   live tenant (expected doc-grounded value: `User:M365Copilot`); record the
   observed shape in `docs/specs/ai-findings-build-spec.md` conventions.
2. Update `Private/Analyze/ppa-coverage-provenance.json`: add a `rowOverrides`
   entry for `copilot`/`retention` with `live-verified` + the observed grounding.
3. Add the analyzer cell mapping in `Private/Analyze/Get-PpaCoverageModel.ps1`
   (a Copilot branch in the retention contribution, mirroring the Copilot x DLP
   branch) with pinned tests.
4. Un-hold the cell: remove the `Held` short-circuit; the cell joins the state
   enum and the totals. Update the pinned held-cell tests to pin the new states.
5. Confirm interim snapshots diff cleanly: run the delta over a pre-activation
   and post-activation snapshot pair; the AppRetentionPolicy objects captured
   throughout must compare without spurious Added/Removed.

## 2. Documented-only provenance upgrades (provisional markers)

These columns render the dagger marker ("property shape documented but not yet
verified on a live tenant") until probed:

- **Auto-labeling column**: verify `Get-AutoSensitivityLabelPolicy` location
  and exception property shapes (`ExchangeLocation`, `SharePointLocation`,
  `OneDriveLocation` + `*Exception`). On success flip
  `ppa-coverage-provenance.json` `columns.autoLabel.provenance` to
  `live-verified`; markers disappear without further code change.
- **Retention column (classic workloads)**: verify
  `Get-RetentionCompliancePolicy` location properties incl.
  `TeamsChannelLocation` / `TeamsChatLocation`. Flip
  `columns.retention.provenance` the same way.
- While probing, also confirm the `All` token semantics assumed by
  `Get-PpaLocationScopeToken` (All vs specific-include lists) for both cmdlet
  families.

## 3. Standing deferred-to-TEST list (unchanged by Wave 4)

Live Wave 2 validation, legacy EXO overlap, collection manifest appendix, IRM
depth, and the departing-employee check remain on the standing list and are not
expanded here.
