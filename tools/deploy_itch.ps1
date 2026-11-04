<#
.SYNOPSIS
    Exports the Windows build of Velvet Parliament and pushes it to itch.io with butler.

.DESCRIPTION
    One-time setup: install butler (https://itchio.itch.io/butler), put it on your PATH,
    and run `butler login`. Then from the project folder:

        .\tools\deploy_itch.ps1 -Target yourname/velvet-parliament
        .\tools\deploy_itch.ps1 -Target yourname/velvet-parliament -Version 0.2.0
        .\tools\deploy_itch.ps1 -BuildOnly

    -Target can also come from the ITCH_TARGET environment variable, and the Godot
    executable from GODOT (defaults to the 4.7.2 console build in Downloads).
#>
param(
    [string]$Target = $env:ITCH_TARGET,
    [string]$Godot = $env:GODOT,
    [string]$Version = "",
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $project "build\windows"
$exe = Join-Path $buildDir "VelvetParliament.exe"

if (-not $Godot) {
    $Godot = "C:\Users\setmk\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
}
if (-not (Test-Path $Godot)) {
    throw "Godot not found at '$Godot'. Pass -Godot <path to Godot console exe> or set GODOT."
}

Write-Host "Exporting Windows build..."
New-Item -ItemType Directory -Force $buildDir | Out-Null
if (Test-Path $exe) { Remove-Item $exe }
& $Godot --headless --path $project --export-release "Windows Desktop" $exe
if (-not (Test-Path $exe) -or (Get-Item $exe).Length -eq 0) {
    throw "Export failed: $exe was not created."
}
Write-Host ("Built {0} ({1:N0} MB)" -f $exe, ((Get-Item $exe).Length / 1MB))

if ($BuildOnly) { return }

if (-not $Target) {
    throw "No itch.io target. Pass -Target yourname/velvet-parliament or set ITCH_TARGET."
}
$butler = Get-Command butler -ErrorAction SilentlyContinue
if ($null -eq $butler) {
    throw "butler is not on PATH. Install it from https://itchio.itch.io/butler and run 'butler login' once."
}
if (-not $Version) {
    $Version = Get-Date -Format "yyyy.MM.dd-HHmm"
}

Write-Host "Pushing to ${Target}:windows as version $Version..."
& $butler.Source push $buildDir "${Target}:windows" --userversion $Version
if ($LASTEXITCODE -ne 0) { throw "butler push failed." }
Write-Host "Done. Check the build status with: butler status ${Target}:windows"
