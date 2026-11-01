# package_msix.ps1
# Script to package the Flutter application as an MSIX installer.

$ErrorActionPreference = "Stop"

Write-Host "Updating dependencies..."
flutter pub get

Write-Host "Building MSIX..."
# This command uses the configuration in pubspec.yaml
dart run msix:create

Write-Host "Packaging complete."
Write-Host "Check the 'build/windows/runner/msix' directory for the MSIX file."
