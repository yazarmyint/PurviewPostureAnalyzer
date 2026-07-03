# Invoke-PpaReadCmdlet.ps1 - the read-only collector wrapper.
# Every tenant read goes through here. It runs a single Get-* cmdlet, captures any
# failure, and NEVER throws - so one missing cmdlet or access-denied degrades a single
# finding instead of failing the run (graceful degradation, PLAN.md section 2 & 9).
# ASCII-only source (Windows PowerShell 5.1).
#
# Read-only note: the cmdlet is invoked indirectly via the call operator on a string
# ($Name), so no mutating "Verb-Noun" literal ever appears here or in callers - callers
# pass the cmdlet name as a string (e.g. Invoke-PpaReadCmdlet -Name 'Get-Label').

Set-StrictMode -Off

function Invoke-PpaReadCmdlet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [hashtable]$Arguments = @{}
    )

    # Guardrail: only ever dispatch read verbs. Refuse anything that could mutate.
    $verb = ($Name -split '-', 2)[0]
    if ($verb -notin @('Get', 'Search', 'Test', 'Resolve')) {
        Write-Verbose "Invoke-PpaReadCmdlet: refused non-read cmdlet '$Name'."
        return [pscustomobject]@{ Name = $Name; Status = 'Blocked'; Data = @(); Error = "Refused non-read cmdlet '$Name'." }
    }

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        Write-Verbose "Invoke-PpaReadCmdlet: $Name -> CommandNotFound (session not connected, or module not imported)."
        return [pscustomobject]@{ Name = $Name; Status = 'CommandNotFound'; Data = @(); Error = "Cmdlet '$Name' is not available in this session." }
    }

    try {
        $result = & $Name @Arguments -ErrorAction Stop
        Write-Verbose ("Invoke-PpaReadCmdlet: {0} -> Ok ({1} object(s))." -f $Name, (@($result).Count))
        return [pscustomobject]@{ Name = $Name; Status = 'Ok'; Data = @($result); Error = $null }
    }
    catch {
        $msg = [string]$_.Exception.Message
        $status = if ($msg -match '(?i)access\s+is\s+denied|not\s+authorized|insufficient|permission|unauthorized|forbidden|isn.t connected|no active connection|not connected|connect-') { 'AccessDenied' } else { 'Error' }
        Write-Verbose ("Invoke-PpaReadCmdlet: {0} -> {1} [{2}]: {3}" -f $Name, $status, $_.Exception.GetType().Name, $msg)
        return [pscustomobject]@{ Name = $Name; Status = $status; Data = @(); Error = $msg }
    }
}
