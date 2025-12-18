$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

$changelogPath = Join-Path $projectRoot "CHANGELOG.md"
$pubspecPath = Join-Path $projectRoot "flutter_application\pubspec.yaml"

# Read the latest version from CHANGELOG.md
$changelogContent = Get-Content $changelogPath -Raw
# Match version like [0.3.3-beta] or [1.0.0]
if ($changelogContent -match "## \[(\d+\.\d+\.\d+(-[a-zA-Z0-9]+)?)\]") {
    $latestVersion = $matches[1]
    Write-Host "Found latest version in CHANGELOG: $latestVersion"
} else {
    Write-Error "Could not find version in CHANGELOG.md"
    exit 1
}

$content = Get-Content $pubspecPath -Raw -Encoding UTF8

# Find current version in pubspec to determine build number
if ($content -match "(?m)^version: (\d+\.\d+\.\d+(-[a-zA-Z0-9]+)?)\+(\d+)") {
    $currentPubspecVersion = $matches[1]
    $currentBuild = [int]$matches[3]
    
    if ($latestVersion -ne $currentPubspecVersion) {
        # Version changed, reset build number
        $newBuild = 1
        Write-Host "Version changed from $currentPubspecVersion to $latestVersion. Resetting build number to 1."
    } else {
        # Version same, increment build number
        $newBuild = $currentBuild + 1
        Write-Host "Version is same. Incrementing build number to $newBuild."
    }
    
    $newVersionLine = "version: $latestVersion+$newBuild"
    
    $content = $content -replace "(?m)^version: .*", $newVersionLine
    $content | Set-Content $pubspecPath -Encoding UTF8 -NoNewline
    Write-Host "Updated pubspec.yaml to $newVersionLine"
} else {
    # If format doesn't match exactly (maybe no build number or different format), just set it
    Write-Warning "Could not parse current version in pubspec.yaml. Setting to $latestVersion+1"
    $newVersionLine = "version: $latestVersion+1"
    $content = $content -replace "(?m)^version: .*", $newVersionLine
    $content | Set-Content $pubspecPath -Encoding UTF8 -NoNewline
}

# Copy CHANGELOG.md to flutter_application/CHANGELOG.md
$destChangelog = Join-Path $projectRoot "flutter_application\CHANGELOG.md"
Copy-Item -Path $changelogPath -Destination $destChangelog -Force
Write-Host "Copied CHANGELOG.md to $destChangelog"
