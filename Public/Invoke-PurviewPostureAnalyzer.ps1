# Invoke-PurviewPostureAnalyzer.ps1 - the entry point. Orchestrates the pipeline:
#   run context -> collect (read-only) -> analyze -> assemble -> render HTML + export JSON.
# Graceful degradation: each collector/analyzer is wrapped so one failure yields a
# Verify-manually placeholder section and the run continues (PLAN.md section 2 & 9).
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function Invoke-PurviewPostureAnalyzer {
    [CmdletBinding()]
    param(
        [string]$OutputDirectory,
        [string]$Organization,
        [datetime]$AsOf = (Get-Date)
    )

    # Resolve the output directory to an ABSOLUTE path against the caller's PowerShell location.
    # A relative path handed to .NET file APIs (WriteAllText) would otherwise resolve against the
    # process current directory - often the user home - not the PowerShell location, which is why
    # a relative -OutputDirectory could land somewhere unexpected.
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = 'Outputs' }
    if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
        $OutputDirectory = Join-Path -Path (Get-Location).Path -ChildPath $OutputDirectory
    }
    $OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

    $meta = Get-PpaRunContext -Organization $Organization -AsOf $AsOf

    # ---- SESSION DIAGNOSTICS (Verbose) ----
    # Confirm the read sessions the collectors depend on. Run with -Verbose to see this and
    # every per-cmdlet outcome (Invoke-PpaReadCmdlet logs each Get-* call and its result/error).
    Write-Verbose 'Checking read sessions (run with -Verbose for full collector diagnostics)...'
    foreach ($probe in @('Get-Label', 'Get-DlpCompliancePolicy', 'Get-OrganizationConfig')) {
        $available = [bool](Get-Command -Name $probe -ErrorAction SilentlyContinue)
        Write-Verbose ("  session cmdlet {0}: {1}" -f $probe, ($(if ($available) { 'available' } else { 'NOT available - session not connected?' })))
    }
    $conn = Invoke-PpaReadCmdlet -Name 'Get-ConnectionInformation'
    if ($conn.Status -eq 'Ok') {
        foreach ($c in @($conn.Data)) { Write-Verbose ("  active connection: {0} ({1})" -f $c.ConnectionUri, $c.UserPrincipalName) }
        if (@($conn.Data).Count -eq 0) { Write-Verbose '  active connection: NONE (Connect-IPPSSession / Connect-ExchangeOnline not established)' }
    }

    # ---- COLLECT (read-only; a failure is captured, logged, and yields $null) ----
    $collectorErrors = @{}
    $collect = {
        param([string]$Name, [scriptblock]$Block)
        try { & $Block }
        catch {
            $collectorErrors[$Name] = $_.Exception.Message
            Write-Warning ("Collector '{0}' failed: {1}" -f $Name, $_.Exception.Message)
            Write-Verbose ("Collector '{0}' exception [{1}]:`n{2}`n{3}" -f $Name, $_.Exception.GetType().FullName, $_.Exception.Message, $_.ScriptStackTrace)
            $null
        }
    }
    $rawLabels = & $collect 'Sensitivity Labels'   { Get-PpaSensitivityLabels }
    $rawDlp    = & $collect 'Data Loss Prevention' { Get-PpaDlp }
    $rawRet    = & $collect 'Retention'            { Get-PpaRetention }
    $rawIrm    = & $collect 'Insider Risk'         { Get-PpaInsiderRisk }
    $rawAud    = & $collect 'Audit'                { Get-PpaAudit }
    $rawEd     = & $collect 'eDiscovery'           { Get-PpaEdiscovery }
    $rawCc     = & $collect 'Comms Compliance'     { Get-PpaCommsCompliance }
    $rawDspm   = & $collect 'DSPM for AI'          { Get-PpaDspmAi }

    # Static maps: SIT tiering + license annotations (never detection - decision D9).
    $sitMap = Get-PpaSitTierMap
    $licMap = Get-PpaLicenseRequirements
    $hasSiteLabels = $false
    if ($rawLabels) {
        $hasSiteLabels = @($rawLabels.labels.items | Where-Object { $_.scopes -contains 'Site' -or $_.scopes -contains 'UnifiedGroup' }).Count -gt 0
    }

    # ---- ANALYZE (null raw or analyzer error -> Verify-manually error section) ----
    # The error section carries the REAL reason: the captured collector exception if the collector
    # threw, otherwise the analyzer's exception message - not a generic placeholder.
    $analyze = {
        param([string]$Id, [string]$Title, [string]$Group, [string]$Icon, [string]$Tag, $Raw, [scriptblock]$Block)
        if ($null -eq $Raw) {
            $why = if ($collectorErrors.ContainsKey($Title)) { "Collector error: " + $collectorErrors[$Title] } else { 'Collector returned no data (not connected, missing module, or access denied). Re-run with -Verbose for the underlying cmdlet errors.' }
            return (New-PpaErrorSection -Id $Id -Title $Title -Group $Group -GroupIcon $Icon -GroupTag $Tag -Message $why)
        }
        try { & $Block }
        catch {
            Write-Warning ("Analyzer '{0}' failed: {1}" -f $Title, $_.Exception.Message)
            Write-Verbose ("Analyzer '{0}' exception [{1}]:`n{2}`n{3}" -f $Title, $_.Exception.GetType().FullName, $_.Exception.Message, $_.ScriptStackTrace)
            New-PpaErrorSection -Id $Id -Title $Title -Group $Group -GroupIcon $Icon -GroupTag $Tag -Message ("Analyzer error: " + $_.Exception.Message)
        }
    }

    $sections = @(
        & $analyze 'Sensitivity_Labels' 'Sensitivity Labels' 'Microsoft Information Protection' 'fas fa-shield-alt' '' $rawLabels { Invoke-PpaLabelAnalyzer -Raw $Raw -AsOf $AsOf -LicenseMap $licMap }
        & $analyze 'Data_Loss_Prevention' 'Data Loss Prevention' 'Microsoft Information Protection' 'fas fa-shield-alt' '' $rawDlp { Invoke-PpaDlpAnalyzer -Raw $Raw -AsOf $AsOf -LicenseMap $licMap -SitTierMap $sitMap }
        & $analyze 'Retention' 'Retention & Records' 'Data Lifecycle & Records' 'fas fa-archive' '' $rawRet { Invoke-PpaRetentionAnalyzer -Raw $Raw -LicenseMap $licMap }
        & $analyze 'Insider_Risk' 'Insider Risk Management' 'Insider Risk' 'fas fa-user-secret' '' $rawIrm { Invoke-PpaInsiderRiskAnalyzer -Raw $Raw -LicenseMap $licMap }
        & $analyze 'Audit' 'Audit' 'Discovery & Response' 'fas fa-search' '' $rawAud { Invoke-PpaAuditAnalyzer -Raw $Raw -LicenseMap $licMap }
        & $analyze 'eDiscovery' 'eDiscovery' 'Discovery & Response' 'fas fa-search' '' $rawEd { Invoke-PpaEdiscoveryAnalyzer -Raw $Raw -LicenseMap $licMap }
        & $analyze 'Communication_Compliance' 'Communication Compliance' 'Insider Risk' 'fas fa-user-secret' '' $rawCc { Invoke-PpaCommsComplianceAnalyzer -Raw $Raw -LicenseMap $licMap }
        & $analyze 'DSPM_for_AI' 'DSPM for AI - Copilot Data Security' 'AI Security' 'fas fa-robot' 'NEW' $rawDspm { Invoke-PpaDspmAiAnalyzer -Raw $Raw -LicenseMap $licMap -HasSiteLabels:$hasSiteLabels }
    )

    # ---- DEGRADED-SECTION SUMMARY (visible without -Verbose) ----
    $degraded = @($sections | Where-Object { @($_.findings | Where-Object { $_.id -like '*-ERR' }).Count -gt 0 })
    if ($degraded.Count -gt 0) {
        Write-Warning ("{0} section(s) degraded to Verify manually: {1}. Expand each finding's Remarks for the error, or re-run with -Verbose for the underlying cmdlet failures." -f $degraded.Count, ((@($degraded).title) -join ', '))
    }

    # ---- LICENSE-CONTEXT NOTE (assume E5, annotate tier - decision D9) ----
    $licNote = if ($licMap -and $licMap.contextNote) { [string]$licMap.contextNote }
               else { 'This report assumes Microsoft 365 E5 (or equivalent) licensing when judging Purview workloads and does not read the tenant subscriptions; findings marked Requires note the tier the feature needs.' }
    $licBlock = [pscustomobject]@{ note = $licNote }

    # ---- ASSEMBLE -> RENDER (HTML primary) + EXPORT (JSON) ----
    $normalized = ConvertTo-PpaNormalized -Meta $meta -Licensing $licBlock -Sections $sections -Observations @()

    $stamp = $AsOf.ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $reportsDir = Join-Path (Join-Path $OutputDirectory "PurviewPosture-$stamp") 'reports'

    # Create the timestamped reports directory BEFORE any write (-Force is idempotent and creates
    # every missing parent). The path is absolute, so New-Item and the .NET writes agree on it.
    New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null

    $htmlPath = Join-Path $reportsDir 'posture-report.html'
    $jsonPath = Join-Path $reportsDir 'posture-report.json'
    [System.IO.File]::WriteAllText($htmlPath, (Export-PpaHtmlReport -Normalized $normalized), (New-Object System.Text.UTF8Encoding($false)))
    [void](Export-PpaJson -Normalized $normalized -Path $jsonPath)

    # Only report success once both files are actually on disk. If a write failed, let the failure
    # surface instead of returning paths that do not exist.
    if (-not (Test-Path -LiteralPath $htmlPath) -or -not (Test-Path -LiteralPath $jsonPath)) {
        throw "Report generation did not write its output to '$reportsDir'."
    }

    Write-Host "Report : $htmlPath"
    Write-Host "JSON   : $jsonPath"
    return [pscustomobject]@{ HtmlPath = $htmlPath; JsonPath = $jsonPath; Normalized = $normalized }
}
