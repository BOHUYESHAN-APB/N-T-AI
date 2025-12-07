# package_msi.ps1
# Script to package the Flutter application as an MSI installer using flutter_distributor.

$ErrorActionPreference = "Stop"

Write-Host "Checking for flutter_distributor..."
if (-not (Get-Command flutter_distributor -ErrorAction SilentlyContinue)) {
    Write-Host "flutter_distributor not found. Installing..."
    dart pub global activate flutter_distributor
} else {
    Write-Host "flutter_distributor is already installed."
}

# Check for WiX Toolset (required for MSI)
if (-not (Get-Command light -ErrorAction SilentlyContinue)) {
    Write-Warning "WiX Toolset (light.exe) not found in PATH."
    Write-Warning "MSI packaging requires WiX Toolset v3.x or v4.x."
    Write-Warning "Please install it from: https://wixtoolset.org/"
    Write-Warning "After installation, add it to your PATH and restart this script."
    # We don't exit here because maybe it's aliased or user wants to try anyway, 
    # but usually it will fail.
    Read-Host "Press Enter to continue anyway (or Ctrl+C to cancel)..."
}

Write-Host "Cleaning previous builds..."
flutter clean

Write-Host "Building and Packaging MSI..."
# Using the 'release' release defined in distribute_options.yaml
flutter_distributor package --platform windows --targets msi

Write-Host "Packaging complete."
Write-Host "Check the 'dist' directory for the MSI file."
