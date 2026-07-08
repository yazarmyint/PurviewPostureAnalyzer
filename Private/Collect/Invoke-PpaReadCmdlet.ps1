# Invoke-PpaReadCmdlet.ps1 - the read-only collector wrapper, plus the run manifest it feeds.
# Every tenant read goes through here. It runs a single Get-* cmdlet, captures any
# failure, and NEVER throws - so one missing cmdlet or access-denied degrades a single
# finding instead of failing the run (graceful degradation, PLAN.md section 2 & 9).
# ASCII-only source (Windows PowerShell 5.1).
#
# Read-only note: the cmdlet is invoked indirectly via the call operator on a string
# ($Name), so no mutating "Verb-Noun" literal ever appears here or in callers - callers
# pass the cmdlet name as a string (e.g. Invoke-PpaReadCmdlet -Name 'Get-Label').
#
# Run manifest (F-008): the chokepoint records every dispatched read - cmdlet name,
# resulting status, object count, UTC timestamp - into module-script state that the
# orchestrator writes alongside the report. METADATA ONLY: arguments, filter strings and
# returned data are NEVER recorded, so this on-disk artifact cannot widen the data surface.
# Accumulation is a no-op unless a run started it (Initialize-PpaRunManifest), and the
# recording sits OUTSIDE the verb guardrail - it never touches the read-only check.

Set-StrictMode -Off

# Module-script state for the run manifest. $null when no run is active.
$script:PpaRunManifest = $null       # List[object] of per-cmdlet entries
$script:PpaRunManifestInfo = $null   # run header (startedAt, PowerShell edition/version)

function Initialize-PpaRunManifest {
    # Begin a run manifest: reset the entry list and stamp the run-start header. PS 5.1-safe.
    [CmdletBinding()]
    param()
    $script:PpaRunManifest = New-Object System.Collections.Generic.List[object]
    $script:PpaRunManifestInfo = [ordered]@{
        startedAt = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        psEdition = [string]$PSVersionTable.PSEdition
        psVersion = [string]$PSVersionTable.PSVersion
    }
}

function Write-PpaRunManifestEntry {
    # Record ONE dispatched read. Metadata only - cmdlet name, status, object count, UTC
    # timestamp; never arguments or returned data. No-op unless a run is active.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status,
        [int]$Count = 0
    )
    if ($null -eq $script:PpaRunManifest) { return }
    [void]$script:PpaRunManifest.Add([pscustomobject][ordered]@{
        cmdlet = $Name
        status = $Status
        count  = $Count
        at     = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    })
}

function Get-PpaRunManifest {
    # Assemble the manifest object (run header + per-cmdlet entries), or $null when no run
    # is active. Pure - never touches disk.
    [CmdletBinding()]
    param([string]$PpaVersion = '')
    if ($null -eq $script:PpaRunManifest) { return $null }
    return [pscustomobject][ordered]@{
        tool          = 'PurviewPostureAnalyzer'
        kind          = 'run-manifest'
        schemaVersion = [pscustomobject][ordered]@{ major = 1; minor = 0 }
        ppaVersion    = [string]$PpaVersion
        startedAt     = [string]$script:PpaRunManifestInfo.startedAt
        endedAt       = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        powerShell    = [pscustomobject][ordered]@{
            edition = [string]$script:PpaRunManifestInfo.psEdition
            version = [string]$script:PpaRunManifestInfo.psVersion
        }
        cmdlets       = @($script:PpaRunManifest.ToArray())
    }
}

function Export-PpaRunManifest {
    # Write the run manifest as JSON alongside the report (fixed name in the timestamped
    # reports dir, like posture-report.json). Metadata only, so it is safe unredacted and
    # there is nothing to redact. Returns the path, or $null when no run is active.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [string]$PpaVersion = ''
    )
    $model = Get-PpaRunManifest -PpaVersion $PpaVersion
    if ($null -eq $model) { return $null }
    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }
    $path = Join-Path $Directory 'posture-run-manifest.json'
    [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $model -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("Manifest : {0} ({1} cmdlet call(s) recorded; metadata only - names, statuses, counts, timestamps)" -f $path, @($model.cmdlets).Count)
    return $path
}

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
        Write-PpaRunManifestEntry -Name $Name -Status 'Blocked' -Count 0
        return [pscustomobject]@{ Name = $Name; Status = 'Blocked'; Data = @(); Error = "Refused non-read cmdlet '$Name'." }
    }

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        Write-Verbose "Invoke-PpaReadCmdlet: $Name -> CommandNotFound (session not connected, or module not imported)."
        Write-PpaRunManifestEntry -Name $Name -Status 'CommandNotFound' -Count 0
        return [pscustomobject]@{ Name = $Name; Status = 'CommandNotFound'; Data = @(); Error = "Cmdlet '$Name' is not available in this session." }
    }

    try {
        $result = & $Name @Arguments -ErrorAction Stop
        Write-Verbose ("Invoke-PpaReadCmdlet: {0} -> Ok ({1} object(s))." -f $Name, (@($result).Count))
        Write-PpaRunManifestEntry -Name $Name -Status 'Ok' -Count (@($result).Count)
        return [pscustomobject]@{ Name = $Name; Status = 'Ok'; Data = @($result); Error = $null }
    }
    catch {
        $msg = [string]$_.Exception.Message
        $status = if ($msg -match '(?i)access\s+is\s+denied|not\s+authorized|insufficient|permission|unauthorized|forbidden|isn.t connected|no active connection|not connected|connect-') { 'AccessDenied' } else { 'Error' }
        Write-Verbose ("Invoke-PpaReadCmdlet: {0} -> {1} [{2}]: {3}" -f $Name, $status, $_.Exception.GetType().Name, $msg)
        Write-PpaRunManifestEntry -Name $Name -Status $status -Count 0
        return [pscustomobject]@{ Name = $Name; Status = $status; Data = @(); Error = $msg }
    }
}
