# ConvertTo-PpaLogoDataUri.ps1 - UX-2: encode a client logo image as a data: URI so the
# HTML report stays fully self-contained (offline by design - no external asset references).
# Validation is deliberately strict and terminating: a bad logo must fail the run up front,
# never produce a report with a broken image slot.
# ASCII-only source (Windows PowerShell 5.1).

Set-StrictMode -Off

function ConvertTo-PpaLogoDataUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Path
    )

    # Resolve relative paths against the caller's PowerShell location before touching
    # .NET file APIs (same rule as -OutputDirectory in the orchestrator - the process
    # current directory is not the PowerShell location).
    $fullPath = $Path
    if (-not [System.IO.Path]::IsPathRooted($fullPath)) {
        $fullPath = Join-Path -Path (Get-Location).Path -ChildPath $fullPath
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Logo file not found: '$Path'."
    }

    # Extension whitelist: the report embeds the bytes verbatim, so only formats every
    # browser renders from a data: URI are accepted.
    $mime = switch ([System.IO.Path]::GetExtension($fullPath).ToLower()) {
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        default { throw "Logo file '$Path' has an unsupported extension. Allowed types: .png, .jpg, .jpeg." }
    }

    # ReadAllBytes throws a terminating error on an unreadable file (locked/no access),
    # which is exactly the fail-fast behavior wanted here.
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    if ($bytes.Length -gt 500KB) {
        Write-Warning ("Logo file '{0}' is {1:N0} KB; embedding it grows every HTML report by ~{2:N0} KB. Consider an image under 500 KB." -f $Path, [math]::Round($bytes.Length / 1KB), [math]::Round(($bytes.Length * 4 / 3) / 1KB))
    }

    return ('data:{0};base64,{1}' -f $mime, [System.Convert]::ToBase64String($bytes))
}
