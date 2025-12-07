$baseUrl = "https://unpkg.com"
$dest = "assets/excalidraw"

# Ensure destination exists
if (!(Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }

# Function to download file
function Download-File {
    param ($url, $output)
    Write-Host "Downloading $url to $output..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing
    } catch {
        Write-Error "Failed to download $url : $_"
    }
}

# 1. React & ReactDOM
Download-File "$baseUrl/react@18.2.0/umd/react.production.min.js" "$dest/react.production.min.js"
Download-File "$baseUrl/react-dom@18.2.0/umd/react-dom.production.min.js" "$dest/react-dom.production.min.js"

# 2. Excalidraw UMD
# Note: The UMD build might be in a specific path. Checking typical path.
# If this fails, we might need to use a specific version or path.
# Using a known working version for stability.
$excalidrawVersion = "0.17.6" 
Download-File "$baseUrl/@excalidraw/excalidraw@$excalidrawVersion/dist/excalidraw.production.min.js" "$dest/excalidraw.production.min.js"
Download-File "$baseUrl/@excalidraw/excalidraw@$excalidrawVersion/dist/excalidraw.min.js.map" "$dest/excalidraw.min.js.map"

# 3. Excalidraw Assets (Fonts, Locales)
# These are usually loaded dynamically by Excalidraw. We need to download them and set assetPath.
# Common assets: Virgil.woff2, Cascadia.woff2, locales.
# We will download a few key ones.
$assetsDest = "$dest/assets"
if (!(Test-Path $assetsDest)) { New-Item -ItemType Directory -Path $assetsDest | Out-Null }

$assetBaseUrl = "$baseUrl/@excalidraw/excalidraw@$excalidrawVersion/dist/excalidraw-assets"

Download-File "$assetBaseUrl/Virgil.woff2" "$assetsDest/Virgil.woff2"
Download-File "$assetBaseUrl/Cascadia.woff2" "$assetsDest/Cascadia.woff2"
Download-File "$assetBaseUrl/locales.json" "$assetsDest/locales.json"
# Download a few common languages
Download-File "$assetBaseUrl/zh-CN.json" "$assetsDest/zh-CN.json"

Write-Host "Download complete."
