# Logo.Tests.ps1 - UX-2: client logo embedded as a data: URI. Helper validation (path,
# extension whitelist, size warning), exporter slot behavior (img when a URI is passed,
# nothing - and no dashed placeholder - when not), the dead-CSS regression for the retired
# logo-ph rule, and the Invoke fail-fast contract (a bad -LogoPath must error before any
# collector runs). Pester 5. ASCII-only source.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    foreach ($file in (Get-ChildItem -Path (Join-Path $script:RepoRoot 'Private') -Recurse -Filter '*.ps1')) { . $file.FullName }

    # The Invoke fail-fast test needs the module's own scope for collector mocks.
    Import-Module (Join-Path $script:RepoRoot 'PurviewPostureAnalyzer.psd1') -Force

    function Read-PpaFixture([string]$RelPath) {
        [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot $RelPath), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }

    # One normalized fixture for the exporter slot tests (standard: Northwind Health).
    $std = Read-PpaFixture 'Samples\sample-normalized.json'
    $script:StdNorm = ConvertTo-PpaNormalized -Meta $std.meta -Licensing $std.licensing -Sections $std.sections
}

AfterAll {
    Remove-Module PurviewPostureAnalyzer -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-PpaLogoDataUri (UX-2 helper)' {
    BeforeAll {
        # Content is irrelevant to the helper (extension drives the mime type), so tiny
        # placeholder byte files are enough for the encoding tests.
        $script:PngPath = Join-Path $TestDrive 'fixture-logo.png'
        [System.IO.File]::WriteAllBytes($script:PngPath, [byte[]](137, 80, 78, 71, 13, 10, 26, 10))
        $script:JpgPath = Join-Path $TestDrive 'fixture-logo.jpg'
        [System.IO.File]::WriteAllBytes($script:JpgPath, [byte[]](255, 216, 255, 224))
        $script:JpegPath = Join-Path $TestDrive 'fixture-logo.jpeg'
        [System.IO.File]::WriteAllBytes($script:JpegPath, [byte[]](255, 216, 255, 224))
        $script:BadExtPath = Join-Path $TestDrive 'fixture-logo.gif'
        [System.IO.File]::WriteAllBytes($script:BadExtPath, [byte[]](71, 73, 70, 56))
    }
    It 'throws (terminating) when the path does not exist' {
        { ConvertTo-PpaLogoDataUri -Path (Join-Path $TestDrive 'no-such-logo.png') } | Should -Throw '*Logo file not found*'
    }
    It 'throws on a non-whitelisted extension, naming the allowed types' {
        { ConvertTo-PpaLogoDataUri -Path $script:BadExtPath } | Should -Throw '*Allowed types: .png, .jpg, .jpeg*'
    }
    It 'encodes a .png file with the image/png mime prefix and the exact base64 payload' {
        $uri = ConvertTo-PpaLogoDataUri -Path $script:PngPath
        $uri | Should -Match '^data:image/png;base64,'
        $uri | Should -Be ('data:image/png;base64,' + [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:PngPath)))
    }
    It 'encodes .jpg and .jpeg files with the image/jpeg mime prefix' {
        (ConvertTo-PpaLogoDataUri -Path $script:JpgPath)  | Should -Match '^data:image/jpeg;base64,'
        (ConvertTo-PpaLogoDataUri -Path $script:JpegPath) | Should -Match '^data:image/jpeg;base64,'
    }
    It 'warns when the source file exceeds 500 KB (HTML bloat note), but still encodes' {
        $bigPath = Join-Path $TestDrive 'fixture-logo-big.png'
        [System.IO.File]::WriteAllBytes($bigPath, (New-Object byte[] (500KB + 1)))
        $uri = ConvertTo-PpaLogoDataUri -Path $bigPath -WarningVariable warns -WarningAction SilentlyContinue
        @($warns).Count | Should -Be 1
        [string]$warns[0] | Should -Match '500 KB'
        $uri | Should -Match '^data:image/png;base64,'
    }
    It 'does NOT warn at or under 500 KB' {
        $okPath = Join-Path $TestDrive 'fixture-logo-ok.png'
        [System.IO.File]::WriteAllBytes($okPath, (New-Object byte[] (500KB)))
        $null = ConvertTo-PpaLogoDataUri -Path $okPath -WarningVariable warns -WarningAction SilentlyContinue
        @($warns).Count | Should -Be 0
    }
}

Describe 'Export-PpaHtmlReport logo slot (UX-2)' {
    It 'renders one <img class="logo"> carrying the passed data URI, and no logo-ph, when -LogoDataUri is set' {
        $uri = 'data:image/png;base64,UX2TESTPAYLOAD='
        $html = Export-PpaHtmlReport -Normalized $script:StdNorm -IsSample -LogoDataUri $uri
        ([regex]::Matches($html, '<img class="logo"')).Count | Should -Be 1
        $html | Should -Match ('src="' + [regex]::Escape($uri) + '" alt="Client logo"')
        $html | Should -Not -Match 'logo-ph'
    }
    It 'renders NOTHING in the slot without -LogoDataUri: no logo img and no placeholder' {
        $html = Export-PpaHtmlReport -Normalized $script:StdNorm -IsSample
        $html | Should -Not -Match '<img class="logo"'
        $html | Should -Not -Match 'logo-ph'
    }
    It 'REGRESSION: the string "logo-ph" appears nowhere in Private/Render (dead CSS, F-012 style)' {
        $hits = @(Get-ChildItem -Path (Join-Path $script:RepoRoot 'Private\Render') -Recurse -Filter '*.ps1' | Where-Object {
            [System.IO.File]::ReadAllText($_.FullName) -match 'logo-ph'
        })
        @($hits).Count | Should -Be 0
    }
}

Describe 'Invoke-PurviewPostureAnalyzer -LogoPath (UX-2 fail fast)' {
    It 'a bad -LogoPath errors BEFORE any collection: the first collector is never invoked and nothing is written' {
        Mock -ModuleName PurviewPostureAnalyzer Get-PpaSensitivityLabels { $null }
        $outDir = Join-Path $TestDrive 'logo-failfast-out'
        { Invoke-PurviewPostureAnalyzer -OutputDirectory $outDir -LogoPath (Join-Path $TestDrive 'missing-logo.png') } |
            Should -Throw '*Logo file not found*'
        Should -Invoke Get-PpaSensitivityLabels -ModuleName PurviewPostureAnalyzer -Exactly -Times 0
        Test-Path -LiteralPath $outDir | Should -BeFalse
    }
}
