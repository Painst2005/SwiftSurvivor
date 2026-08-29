$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$scratchPath = Join-Path $projectRoot ".build-sdl-package"
$outputDir = Join-Path $scratchPath "x86_64-unknown-windows-msvc\release"
$sourceExe = Join-Path $outputDir "SwiftSurvivor.exe"
$targetExe = Join-Path $projectRoot "SwiftSurvivor-SDL.exe"
$sdlDll = Join-Path $projectRoot "Vendor\SDL3-3.4.14\lib\x64\SDL3.dll"

swift build -c release --scratch-path $scratchPath
if (-not (Test-Path -LiteralPath $sourceExe)) {
    throw "SDL release executable was not produced at $sourceExe"
}
if (-not (Test-Path -LiteralPath $sdlDll)) {
    throw "SDL3.dll was not found at $sdlDll"
}

Copy-Item -LiteralPath $sourceExe -Destination $targetExe -Force
Copy-Item -LiteralPath $sdlDll -Destination (Join-Path $projectRoot "SDL3.dll") -Force
Write-Output "Created $targetExe"
Write-Output "SDL3 runtime copied to $projectRoot"
