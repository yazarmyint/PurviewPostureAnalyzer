# Disconnect-PurviewPostureSession.ps1 - closes the sessions opened by
# Connect-PurviewPostureSession (Exchange Online + Security & Compliance share
# Disconnect-ExchangeOnline). No Graph session exists (PLAN.md decision D9).
# Best-effort; never throws. ASCII-only source.

Set-StrictMode -Off

function Disconnect-PurviewPostureSession {
    [CmdletBinding()]
    param()

    try {
        if (Get-Command -Name 'Disconnect-ExchangeOnline' -ErrorAction SilentlyContinue) {
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction Stop
        }
    }
    catch { Write-Verbose "Disconnect-ExchangeOnline: $($_.Exception.Message)" }
}
