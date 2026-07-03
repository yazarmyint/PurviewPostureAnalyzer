# Remediation Snippet Review Checklist

> **Every entry below is a DRAFT until a human reviews it.** Nothing in this file or in
> `Data/remediation-catalog.json` is executed by the tool - snippets are display-only text
> rendered inside Improvement / Recommendation findings. Review each row against current
> Microsoft Learn and the tenant reality before treating it as guidance, then tick the box.

Sourcing rule applied (Wave 3 spec, non-negotiable):

- **Cmdlet drafted** only where grounded: verified in this project's probe/spec work, or
  documented at the cited Microsoft Learn URL (fetched 2026-07-03).
- **Portal-path-only** wherever any uncertainty about cmdlet or parameter names existed.
  No cmdlet syntax was invented.

Catalog file: `Data/remediation-catalog.json` (keyed by check ID; joined at render time).

## Cmdlet-bearing drafts (3)

| Reviewed | Check | Cmdlet snippet | Grounding |
|---|---|---|---|
| [ ] | DLP-01 | `Set-DlpCompliancePolicy -Identity "<policy name>" -Mode Enable` | Given verbatim in the Wave 3 spec sourcing rule; `Mode` values (`Test`/`AuditAndNotify`/`Enable`) verified in Wave 2 probe work (CHECK_CATALOG DLP-01/AI-02) |
| [ ] | AI-02 | `Set-DlpCompliancePolicy -Identity "<policy name>" -Mode Enable` | Same cmdlet/parameter as DLP-01; Copilot policy modes verified 2026-07-02 in probe work |
| [ ] | LABELS-03 | `Set-AutoSensitivityLabelPolicy -Identity "<policy name>" -Mode Enable` | Learn cmdlet page (`set-autosensitivitylabelpolicy`): `-Mode` accepted values `Enable, TestWithNotifications, TestWithoutNotifications, Disable, PendingDeletion` - fetched 2026-07-03 |
| [ ] | AUD-01 | `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true` | Learn "Turn auditing on or off" (`purview/audit-log-enable-disable`) shows this command verbatim; must run in **Exchange Online** PowerShell (noted in the snippet comment) - fetched 2026-07-03 |

## Portal-path-only entries (22)

Cmdlets deliberately NOT drafted for these - the write-side cmdlet or its parameters were
not grounded in probe work or the finding's Learn material, so the entry carries only the
portal path and Learn link.

| Reviewed | Check | Portal path (abbreviated) | Renders? |
|---|---|---|---|
| [ ] | LABELS-01 | Information protection > Sensitivity labels | Only if Improvement (zero-taxonomy tenant) |
| [ ] | LABELS-02 | Information protection > Label publishing policies | Only if Improvement |
| [ ] | LABELS-04 | Sensitivity labels > Create label scoped to Groups & sites | Recommendation |
| [ ] | DLP-02 | DLP > Policies > Edit locations > add Teams | Improvement |
| [ ] | DLP-03 | Settings > Device onboarding; DLP > add Devices location | Improvement |
| [ ] | DLP-04 | Data classification > Sensitive info types | Verify manually - never renders |
| [ ] | RET-01 | Data lifecycle management > Retention policies | Informational - never renders |
| [ ] | RET-02 | Data lifecycle management > Adaptive scopes | Improvement |
| [ ] | RET-03 | Data lifecycle management > Label policies > Auto-apply | Improvement |
| [ ] | IRM-01 | Insider risk management > Policies > Create policy | Improvement |
| [ ] | IRM-02 | IRM > Data theft by departing users template | Recommendation |
| [ ] | IRM-03 | IRM > Risky AI usage template | Recommendation |
| [ ] | AUD-02 | Audit > New search (ingestion check) | Verify manually - never renders |
| [ ] | AUD-03 | Audit (Premium) retention | Informational - never renders |
| [ ] | ED-01 | eDiscovery > Cases | Informational - never renders |
| [ ] | ED-02 | eDiscovery Premium capabilities | Informational - never renders |
| [ ] | CC-01 | Communication compliance > Policies > Create policy | Improvement |
| [ ] | AI-01 | DSPM for AI | Informational - never renders |
| [ ] | AI-03 | DLP > Copilot-location rule referencing labels | Recommendation |
| [ ] | AI-04 | DSPM for AI collection policies (PAYG / Agent 365) | Informational - never renders |
| [ ] | AI-05 | Retention policy including the Copilot experiences location | Improvement |
| [ ] | AI-06 | CC > 'Detect Microsoft 365 Copilot interactions' template | Recommendation |

Notes for the reviewer:

- "Never renders" rows exist so the catalog structure stays complete per the spec; the
  renderer gates the block on Improvement/Recommendation status, so those entries only
  surface if a future wave or a different tenant flips the finding's status.
- Under `-RedactNames`, any policy/label names appearing inside snippet text are
  pseudonymized by the P6 redaction pass (current snippets use `"<policy name>"`
  placeholders, so nothing tenant-identifying is embedded).
- Portal paths reflect the unified Microsoft Purview portal as of 2026-07; menu labels
  drift - confirm against the live portal during review.
