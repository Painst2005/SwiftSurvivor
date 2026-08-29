$ErrorActionPreference = "Stop"
swift build -c release --scratch-path .build-game
$outputDir = Join-Path $PSScriptRoot ".build-game\x86_64-unknown-windows-msvc\release"
$sdlDll = Join-Path $PSScriptRoot "Vendor\SDL3-3.4.14\lib\x64\SDL3.dll"
if (-not (Test-Path -LiteralPath $sdlDll)) {
    throw "SDL3.dll was not found at $sdlDll"
}
Copy-Item -LiteralPath $sdlDll -Destination $outputDir -Force
& (Join-Path $outputDir "SwiftSurvivor.exe")
