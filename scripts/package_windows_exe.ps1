# package_windows_exe.ps1
# Build an EXE installer via Inno Setup for the Windows release output.

param(
    [string]$ReleaseDir = "",
    [string]$Version = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$defaultReleaseDir = Join-Path $projectRoot "flutter_application\build\windows\x64\runner\Release"
$defaultOutputDir = Join-Path $projectRoot "flutter_application\build\windows\installer"
$pubspecPath = Join-Path $projectRoot "flutter_application\pubspec.yaml"
$issPath = Join-Path $scriptDir "windows_installer.iss"

if (-not $ReleaseDir) { $ReleaseDir = $defaultReleaseDir }
if (-not $OutputDir) { $OutputDir = $defaultOutputDir }

if (-not (Test-Path $ReleaseDir)) {
    Write-Error "Release directory not found: $ReleaseDir"
    exit 1
}
$ReleaseDir = (Resolve-Path $ReleaseDir).Path

if (-not (Test-Path $issPath)) {
    Write-Error "Inno Setup script not found: $issPath"
    exit 1
}

if (-not $Version) {
    if (Test-Path $pubspecPath) {
        $versionLine = Select-String -Path $pubspecPath -Pattern '^version:' | Select-Object -First 1
        if ($versionLine) {
            $Version = $versionLine.Line.Split(':', 2)[1].Trim()
        }
    }
}

if (-not $Version) { $Version = "0.0.0" }

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}
$OutputDir = (Resolve-Path $OutputDir).Path

Push-Location $scriptDir
$releaseDirRel = Resolve-Path $ReleaseDir -Relative
$outputDirRel = Resolve-Path $OutputDir -Relative
Pop-Location

$compiler = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
if (-not $compiler) {
    Write-Error "Inno Setup Compiler (ISCC.exe) not found. Please install Inno Setup and add it to PATH."
    exit 1
}

Write-Host "=========================================="
Write-Host "   N-T-AI Windows Installer (EXE) Build   "
Write-Host "=========================================="
Write-Host "Release Dir : $ReleaseDir"
Write-Host "Output Dir  : $OutputDir"
Write-Host "Version     : $Version"

$defines = @(
    "/DMySourceDir=`"$releaseDirRel`"",
    "/DMyOutputDir=`"$outputDirRel`"",
    "/DMyAppVersion=$Version"
)

& $compiler.Source @defines $issPath

Write-Host "=========================================="
Write-Host "Installer build complete."
