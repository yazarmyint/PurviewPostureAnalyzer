# PurviewPostureAnalyzer.psm1 - module loader.
# Dot-sources every Private helper and Public entry point, then exports only the public
# functions. ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

$privateFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue)
$publicFiles  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in ($privateFiles + $publicFiles)) {
    try { . $file.FullName }
    catch { throw "Failed to load '$($file.FullName)': $($_.Exception.Message)" }
}

Export-ModuleMember -Function @($publicFiles | ForEach-Object { $_.BaseName })
