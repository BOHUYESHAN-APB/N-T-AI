# build_windows_release.ps1
# 统一构建脚本：打包后端（清理敏感数据）、更新版本、构建前端 Windows Release

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$flutterAppDir = Join-Path $projectRoot "flutter_application"
$backendDir = Join-Path $projectRoot "backend"
$backendDistDir = Join-Path $backendDir "dist\server"
$frontendServerDir = Join-Path $flutterAppDir "server"

Write-Host "=========================================="
Write-Host "   N-T-AI Windows Release Build Script    "
Write-Host "=========================================="

# Ensure we are in the project root
Set-Location $projectRoot
Write-Host "Working Directory set to: $projectRoot"

# 0. Kill lingering processes to prevent file locks
Write-Host "`n[0/6] Cleaning up running processes..."
$processesToKill = @("server", "flutter_application")
foreach ($procName in $processesToKill) {
    $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "Stopping running process: $procName"
        $procs | Stop-Process -Force
        Start-Sleep -Seconds 1
    }
}

# 1. Update Version
Write-Host "`n[1/5] Updating Version..."
& "$scriptDir\update_version.ps1"

# 2. Build Backend
Write-Host "`n[2/5] Building Python Backend..."
Push-Location $backendDir
# Ensure PyInstaller is installed
# if (-not (Get-Command pyinstaller -ErrorAction SilentlyContinue)) {
#     Write-Host "Installing PyInstaller..."
#     pip install pyinstaller
# }
# Clean previous dist
if (Test-Path "dist") { Remove-Item "dist" -Recurse -Force }
if (Test-Path "build") { Remove-Item "build" -Recurse -Force }

# Run PyInstaller
# Exclude specific patterns if possible via spec, but simpler to clean after.
Write-Host "Running PyInstaller..."
# Explicitly exclude GUI and Data Science libraries that might trigger Qt/heavy dependencies
pyinstaller --noconfirm --onedir --console --name "server" --paths . `
    --exclude-module torch --exclude-module torchvision --exclude-module torchaudio `
    --exclude-module PyQt5 --exclude-module PyQt6 --exclude-module PySide2 --exclude-module PySide6 `
    --exclude-module tkinter --exclude-module matplotlib --exclude-module IPython --exclude-module notebook `
    --add-data "app/static;app/static" --add-data "app/prompts;app/prompts" serve.py

if (-not (Test-Path $backendDistDir)) {
    Write-Error "Backend build failed. Directory not found: $backendDistDir"
    exit 1
}

# 3. Clean Backend Artifacts (Security/Privacy)
Write-Host "`n[3/5] Cleaning Sensitive/Test Data from Backend..."
# Define patterns to exclude/delete
$excludePatterns = @(
    "__pycache__",
    "*.log",
    "temp", "tmp"
)

# Recursively remove general junk from the dist folder
Get-ChildItem -Path $backendDistDir -Recurse | Where-Object {
    $item = $_
    $excludePatterns | ForEach-Object {
        if ($item.Name -like $_) {
            Write-Host "Removing: $($item.FullName)"
            Remove-Item $item.FullName -Recurse -Force
        }
    }
}

# Explicitly remove sensitive data from specific directories
# 1. Reports directory
$staticReportsDir = Join-Path $backendDistDir "_internal\app\static\reports"
if (Test-Path $staticReportsDir) {
    Write-Host "Cleaning sensitive reports from $staticReportsDir..."
    Get-ChildItem -Path $staticReportsDir -Include "*.pptx", "*.docx", "*.xlsx", "*.pdf" -Recurse | Remove-Item -Force
}

# 2. Workspace directory (if it exists inside dist)
$workspaceDir = Join-Path $backendDistDir "workspace"
if (Test-Path $workspaceDir) {
    Write-Host "Removing workspace directory..."
    Remove-Item $workspaceDir -Recurse -Force
}

Pop-Location

# 4. Copy Backend to Frontend (for MSIX/Bundling)
Write-Host "`n[4/5] Copying Clean Backend to Flutter Project..."
if (Test-Path $frontendServerDir) { Remove-Item $frontendServerDir -Recurse -Force }
Copy-Item -Path $backendDistDir -Destination $frontendServerDir -Recurse -Force

# 5. Build Flutter Windows
Write-Host "`n[5/5] Building Flutter Windows Release..."
Push-Location $flutterAppDir
& "C:\Users\BoHuYeShan\flutter\flutter\bin\flutter.bat" clean
& "C:\Users\BoHuYeShan\flutter\flutter\bin\flutter.bat" pub get
& "C:\Users\BoHuYeShan\flutter\flutter\bin\flutter.bat" build windows --release

# 6. Copy Backend to Release Output Directory (Fix for standalone EXE)
$releaseOutputDir = Join-Path $flutterAppDir "build\windows\x64\runner\Release"
$releaseServerDir = Join-Path $releaseOutputDir "server"
Write-Host "`n[6/6] Copying Backend to Release Output Directory: $releaseServerDir"
if (Test-Path $releaseServerDir) { Remove-Item $releaseServerDir -Recurse -Force }
# Ensure the destination parent directory exists
if (-not (Test-Path $releaseOutputDir)) {
    Write-Warning "Release output directory not found at $releaseOutputDir. Flutter build might have failed."
} else {
    Copy-Item -Path $backendDistDir -Destination $releaseServerDir -Recurse -Force
    Write-Host "Backend copied successfully to Release folder."
    
    # Copy VC++ Redist DLLs from backend internal dir to release root (if needed by frontend)
    $serverInternalDir = Join-Path $releaseServerDir "_internal"
    if (Test-Path $serverInternalDir) {
        Write-Host "Checking for VC++ Redist DLLs in $serverInternalDir"
        $dlls = @("MSVCP140.dll", "VCRUNTIME140.dll", "VCRUNTIME140_1.dll")
        foreach ($dll in $dlls) {
            $srcPath = Join-Path $serverInternalDir $dll
            if (Test-Path $srcPath) {
                Write-Host "Copying $dll to release root..."
                Copy-Item $srcPath $releaseOutputDir -ErrorAction SilentlyContinue
            } else {
                Write-Warning "$dll not found in backend _internal directory."
            }
        }
    }
}


# Optional: MSIX Build (if needed)
# dart run msix:create

Write-Host "`n=========================================="
Write-Host "Build Complete!"
Write-Host "Output: $releaseOutputDir"
Write-Host "=========================================="
Pop-Location
