$ErrorActionPreference = "Stop"

$cmake = Get-Command cmake -ErrorAction Stop
$sdkPath = Join-Path $PSScriptRoot "discord_social_sdk"
$buildPath = Join-Path $env:LOCALAPPDATA "ShiftLine\discord-social-sdk-build"

& $cmake.Source -S $sdkPath -B $buildPath -A x64
if ($LASTEXITCODE -ne 0) {
    throw "Discord Social SDK bridge configuration failed"
}

& $cmake.Source --build $buildPath --config Release --target shiftline_discord_bridge
if ($LASTEXITCODE -ne 0) {
    throw "Discord Social SDK bridge build failed"
}