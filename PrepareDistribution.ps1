param(
    [string]$RuntimeRoot = "D:\Swift\Runtimes\6.3.3\usr\bin",
    [string]$Version = "1.0.1"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$exePath = Join-Path $projectRoot "SwiftSurvivor.exe"
$resourcesPath = Join-Path $projectRoot "Resources"
$stagePath = Join-Path $projectRoot "SwiftSurvivor-Portable-$Version"
$zipPath = Join-Path $projectRoot "SwiftSurvivor-Portable-$Version.zip"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "SwiftSurvivor.exe was not found at $exePath"
}
if (-not (Test-Path -LiteralPath $resourcesPath)) {
    throw "Resources folder was not found at $resourcesPath"
}
if (-not (Test-Path -LiteralPath $RuntimeRoot)) {
    throw "Swift runtime folder was not found at $RuntimeRoot"
}

# Keep the staging folder deterministic so no stale DLL can be shipped.
if (Test-Path -LiteralPath $stagePath) {
    Remove-Item -LiteralPath $stagePath -Recurse -Force
}
New-Item -ItemType Directory -Path $stagePath | Out-Null

Copy-Item -LiteralPath $exePath -Destination (Join-Path $stagePath "SwiftSurvivor.exe")
Copy-Item -LiteralPath $resourcesPath -Destination (Join-Path $stagePath "Resources") -Recurse

$sdlDllPath = Join-Path $projectRoot "Vendor\SDL3-3.4.14\lib\x64\SDL3.dll"
if (Test-Path -LiteralPath $sdlDllPath) {
    Copy-Item -LiteralPath $sdlDllPath -Destination $stagePath -Force
}

# Swift loads some modules lazily (for example swift_RegexParser.dll), so
# copying only the executable's static imports is not sufficient. Ship every
# runtime DLL from the matching Swift toolchain.
Get-ChildItem -LiteralPath $RuntimeRoot -Filter "*.dll" -File |
    Copy-Item -Destination $stagePath -Force

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $stagePath "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Output "Created $stagePath"
Write-Output "Created $zipPath"
