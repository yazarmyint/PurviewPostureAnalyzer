# Security Policy

## Reporting a vulnerability

Report security vulnerabilities in Purview Posture Analyzer (PPA) through **GitHub
private vulnerability reporting**, which is the sole reporting channel for this project:

1. Open the repository's **Security** tab, or go directly to
   <https://github.com/yazarmyint/PurviewPostureAnalyzer/security/advisories/new>.
2. Click **Report a vulnerability** and complete the advisory form.

Your report stays private to the maintainer until a fix is coordinated and published.
Please do **not** open a public GitHub issue for a security vulnerability.

> Maintainer action: GitHub private vulnerability reporting must be enabled for this
> repository (Settings -> Code security -> Private vulnerability reporting) before the
> advisory link above will work.

## What is in scope

A security report means a vulnerability **in PPA itself** - for example in its PowerShell
code, in how it establishes or handles the read-only sessions (`Connect-IPPSSession` /
`Connect-ExchangeOnline`), or in the report and JSON it produces (for example, data that
should have been redacted but is emitted).

It does **not** mean a misconfiguration that the tool *discovers and reports* in your own
Microsoft Purview tenant. Those are findings about your environment for you to review and
remediate - not vulnerabilities in this tool. PPA is read-only and never changes tenant
state (see `NOTICE` and the README).

## Project status

PPA is an independent, community-maintained project (see `NOTICE`) - not a Microsoft
product and not covered by Microsoft's security program (MSRC). Security fixes are made on
the current version on the default branch.
