param(
    [string]$Version = "1.4.3"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$flutter = "flutter"
$publish = Join-Path $root "app\build\windows\x64\runner\Release"
$artifacts = Join-Path $root "artifacts"
if (Test-Path $artifacts) { Remove-Item $artifacts -Recurse -Force }

Set-Location (Join-Path $root "app")
& $flutter pub get
& $flutter build windows --release
Set-Location $root

$dotnet = Join-Path $env:LOCALAPPDATA "dotnet\dotnet.exe"
if (-not (Test-Path $dotnet)) { $dotnet = "dotnet" }
& $dotnet tool update -g vpk 2>$null
if ($LASTEXITCODE -ne 0) { & $dotnet tool install -g vpk }

$vpk = Join-Path $env:USERPROFILE ".dotnet\tools\vpk.exe"
if (-not (Test-Path $vpk)) { $vpk = "vpk" }

& $vpk pack --packId MacroRelay --packVersion $Version --packDir $publish --mainExe MacroRelay.exe --packTitle MacroRelay --icon (Join-Path $root "app\windows\runner\resources\app_icon.ico") --outputDir $artifacts
Write-Host "Installer output: $artifacts"
