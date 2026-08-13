param(
    [string]$Version = "1.0.0"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$dotnet = Join-Path $env:LOCALAPPDATA "dotnet\dotnet.exe"
if (-not (Test-Path $dotnet)) { $dotnet = "dotnet" }

$publish = Join-Path $root "publish"
$artifacts = Join-Path $root "artifacts"
if (Test-Path $publish) { Remove-Item $publish -Recurse -Force }
if (Test-Path $artifacts) { Remove-Item $artifacts -Recurse -Force }

& $dotnet publish "$root\src\MacroRelay.App\MacroRelay.App.csproj" `
    -c Release -r win-x64 --self-contained true `
    -p:PublishReadyToRun=true `
    -o $publish

& $dotnet tool update -g vpk 2>$null
if ($LASTEXITCODE -ne 0) {
    & $dotnet tool install -g vpk
}

$vpk = Join-Path $env:USERPROFILE ".dotnet\tools\vpk.exe"
if (-not (Test-Path $vpk)) { $vpk = "vpk" }

& $vpk pack --packId MacroRelay --packVersion $Version --packDir $publish --mainExe MacroRelay.exe --packTitle MacroRelay --outputDir $artifacts

Write-Host "Installer output: $artifacts"
