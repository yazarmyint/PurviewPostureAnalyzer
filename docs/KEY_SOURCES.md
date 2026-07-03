# KEY_SOURCES - normalized object identity audit (Wave 4, Part A.1)

Keying rule (Wave 4 spec section 3.3): **Guid -> Identity -> Name**, first source
present wins. The snapshot writer stamps `_key` / `_keySource` from this table at
capture time; keys are namespaced per type (uniqueness enforced within a type
array). Duplicate keys within a type are disambiguated deterministically
(`#2`, `#3` in stable input order) with a console warning.

None of the current normalized projections carry an `Identity` property, so the
effective sources today are Guid (one type) and Name (everything else).

## Item types (one snapshot object per policy/label/case/...)

| Snapshot type        | Collector                | Source list                    | Key source | Key property |
|----------------------|--------------------------|--------------------------------|------------|--------------|
| SensitivityLabel     | Get-PpaSensitivityLabels | labels.items                   | Guid       | `guid`       |
| LabelPolicy          | Get-PpaSensitivityLabels | policies.items                 | Name       | `name`       |
| AutoLabelPolicy      | Get-PpaSensitivityLabels | autoLabels.items               | Name       | `name`       |
| DlpPolicy            | Get-PpaDlp               | policies.items                 | Name       | `name`       |
| DlpRule              | Get-PpaDlp               | rules.items                    | Name       | `name`       |
| RetentionPolicy      | Get-PpaRetention         | policies.items                 | Name       | `name`       |
| RetentionLabel       | Get-PpaRetention         | labels.items                   | Name       | `name`       |
| InsiderRiskPolicy    | Get-PpaInsiderRisk       | policies.items                 | Name       | `name`       |
| EdiscoveryCase       | Get-PpaEdiscovery        | cases.items                    | Name       | `name`       |
| CopilotDlpPolicy     | Get-PpaDspmAi            | copilotPolicies.items          | Name       | `name`       |
| DspmPolicy           | Get-PpaDspmAi            | dspmPolicies.items             | Name       | `name` (see caveat 1) |
| AppRetentionPolicy   | Get-PpaDspmAi            | appRetention.items             | Name       | `name`       |
| CcCopilotPolicy      | Get-PpaDspmAi            | ccCopilot.items                | Name       | `name`       |

## Singleton summary types (tenant-level state, exactly one object per snapshot)

These blocks carry real posture data (e.g. unified audit on/off) that delta must
diff, but have no natural per-object identity. Rule: each is serialized as a
one-element type array whose object gains a constant `name` equal to the type
name, keyed with `_keySource = "Name"`. A constant name is trivially stable
across snapshots.

| Snapshot type            | Collector               | Source block    |
|--------------------------|-------------------------|-----------------|
| AuditConfig              | Get-PpaAudit            | (root object)   |
| CommsComplianceSummary   | Get-PpaCommsCompliance  | policies (count-only) |
| AdaptiveScopeSummary     | Get-PpaRetention        | adaptiveScopes  |
| RetentionLegacySummary   | Get-PpaDspmAi           | retentionLegacy |
| LabelContainerSummary    | Get-PpaSensitivityLabels| containers      |

## Caveats recorded for design review

1. **DspmPolicy** - `Get-DspmPolicy`'s schema is unverified (0 objects observed in
   the 2026-07-02 sandbox; projection is generic name + property bag). If a live
   object ever arrives without a `Name` property, the item's key is the empty
   string and the writer's duplicate-key disambiguation (`#2`, `#3`...) plus
   console warning applies. That fallback is deterministic within one snapshot
   but NOT stable across snapshots; if TEST-day probing shows real DspmPolicy
   objects without names, keying for this type goes back to design review.
2. **DlpRule** - keyed by `name` alone (rule names are tenant-unique in the
   Microsoft 365 compliance store). `policyName` is carried as a property, not as
   part of the key, so a rule moved between policies classifies as Modified
   rather than Removed+Added.
3. **SensitivityLabel** - the only type with a Guid today; `parentId` references
   another label's Guid and remains a plain property (never part of the key).

## Per-collector outcome enum (A.4)

Emitted by every collector as a root `outcome` property, derived by
`Resolve-PpaCollectorOutcome` (Private/Collect/PpaNormalize.ps1) from the
statuses of every read the collector performed plus the normalized item count:
`Populated | Empty | Partial | AccessDenied | CmdletUnavailable | Failed`.
`Skipped | NotRun` are stamped by the orchestration layer for sections excluded
from a run; a collector that actually ran never reports them.
