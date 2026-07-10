# Test-PpaExoModuleAvailable.ps1 - F-014 guard probe: is the ExchangeOnlineManagement
# module discoverable on this box? Availability only (Get-Module -ListAvailable) -
# deliberately NOT an import and NOT a command probe (a command probe cannot tell
# "module missing" from "module present but not yet imported", and its failure mode
# is its own error). Consumed by the Connect-PurviewPostureSession presence guard,
# which every connect path funnels through. ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function Test-PpaExoModuleAvailable {
    return (@(Get-Module -ListAvailable -Name 'ExchangeOnlineManagement').Count -gt 0)
}
