# Legacy CAMP files (superseded — do not run)

This folder holds the original [OfficeDev/CAMP](https://github.com/OfficeDev/CAMP) engine that
the **Purview Posture Analyzer** module (in the repo root) was derived from and replaces. It is
kept only for reference during transition.

> **Do not run these files against a client/production tenant.**

The legacy code contains behavior this project deliberately removed:

- **Tenant audit-log writes** — `Write-EXOPAdminAuditLog` on start/finish (`CAMP.psm1`).
- **Execution beacon** — `wget http://aka.ms/mcca-execution`.
- **Telemetry** — POSTs tenant domain + organization name to an external endpoint.
- **Automatic module install/update** — `Install-Module -force` / `Update-Module`.
- **Policy-creating remediation** — `Remediation/`, `Templates/` generate scripts that
  `New-DlpCompliancePolicy` (change-making).
- **Prescriptive, geo/SIT, framework-leaning** recommendation model (`DLPImprovementActions/`).

The modernized tool is read-only, collects no content by default, and produces framework-neutral
findings. See the repo root [README.md](../README.md) and
[MODERNIZATION_PLAN.md](../MODERNIZATION_PLAN.md).

The MIT license and Microsoft copyright from CAMP are preserved in the root
[LICENSE](../LICENSE) and attributed in [NOTICE](../NOTICE).
