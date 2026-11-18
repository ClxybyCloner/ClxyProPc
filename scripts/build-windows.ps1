# Builds ClxyPro for Windows (Portable) into dist\:
# - ClxyPro-<version>-Windows-x64.zip: Portable package containing:
#     ClxyPro\
#       ClxyPro.exe
#       data\
#       flutter_windows.dll
#       core\
#         clxy-vpn-core.exe
#         clxy-vpn-tun.exe
#       README.txt
#
# No installer, completely portable. All user data lives in user-data\ beside ClxyPro.exe.

param(
    [string]$AppVersion = ""
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not $AppVersion) {
    $match = Select-String -Path "$root\app\pubspec.yaml" -Pattern '^version:\s*(\d+\.\d+\.\d+)'
    if ($match) {
        $AppVersion = $match.Matches[0].Groups[1].Value
    } else {
        $AppVersion = "1.5.14"
    }
}

Write-Host "=== Building ClxyPro for Windows Portable v$AppVersion ===" -ForegroundColor Cyan

$dist = "$root\dist"
$stage = "$dist\stage"
$appFolder = "$stage\ClxyPro"

if (Test-Path $dist) {
    Remove-Item -Recurse -Force $dist -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force $appFolder | Out-Null
New-Item -ItemType Directory -Force "$appFolder\core" | Out-Null

# 1. Build Flutter App
Write-Host "`n[1/4] Building Flutter Windows desktop app..." -ForegroundColor Green
Push-Location "$root\app"
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
    
    flutter build windows --release --dart-define=APP_VERSION=$AppVersion
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
} finally {
    Pop-Location
}

# Copy Flutter release files
$flutterRelease = "$root\app\build\windows\x64\runner\Release"
if (-not (Test-Path "$flutterRelease\ClxyPro.exe")) {
    throw "Flutter build output not found at $flutterRelease\ClxyPro.exe"
}
Copy-Item "$flutterRelease\*" $appFolder -Recurse -Force

# 2. Build Go Core Executables
Write-Host "`n[2/4] Building Go core sidecar (clxy-vpn-core.exe)..." -ForegroundColor Green
Push-Location "$root\core"
try {
    $coreLdflags = "-s -w -X github.com/ClxybyCloner/ClxyProPc/core/internal/version.Current=$AppVersion"
    go build -trimpath -ldflags $coreLdflags -o "$appFolder\core\clxy-vpn-core.exe" ./cmd/clxy-vpn-core
    if ($LASTEXITCODE -ne 0) { throw "go build clxy-vpn-core failed" }

    Write-Host "`n[3/4] Building Go TUN service (clxy-vpn-tun.exe)..." -ForegroundColor Green
    $tunLdflags = "-s -w -H windowsgui -X github.com/ClxybyCloner/ClxyProPc/core/internal/version.Current=$AppVersion"
    go build -tags with_gvisor -trimpath -ldflags $tunLdflags -o "$appFolder\core\clxy-vpn-tun.exe" ./cmd/clxy-vpn-tun
    if ($LASTEXITCODE -ne 0) { throw "go build clxy-vpn-tun failed" }
} finally {
    Pop-Location
}

# 3. Create Portable README.txt
Write-Host "`n[4/4] Creating portable package and zip archive..." -ForegroundColor Green
$readmeContent = @"
========================================================================
ClxyPro for Windows (Portable) v$AppVersion
========================================================================

Welcome to ClxyPro for Windows!

HOW TO RUN:
1. Extract this entire zip file to any folder of your choice
   (e.g., Desktop, Documents, C:\Tools\ClxyPro, or a USB drive).
2. Double-click "ClxyPro.exe" to launch.

PORTABLE DATA STORAGE:
- All preferences, accounts, logs, and server cache live in a
  "user-data\" folder created next to ClxyPro.exe.
- Nothing is written to %APPDATA%, %LOCALAPPDATA%, or the Windows Registry
  (unless you explicitly enable Auto-start on boot in Settings).
- The app requires NO installer and NO administrator rights for Proxy Mode.
  TUN Mode (Full Device VPN) may ask for elevation on first use.

HOW TO UNINSTALL:
- Simply close ClxyPro and delete this folder.
  Nothing else is left behind.

========================================================================
Source: https://github.com/ClxybyCloner/ClxyProPc
========================================================================
"@
Set-Content -Path "$appFolder\README.txt" -Value $readmeContent -Encoding utf8

# 4. Create Archive
$zipName = "ClxyPro-$AppVersion-Windows-x64.zip"
$zipPath = "$dist\$zipName"

Compress-Archive -Path $appFolder -DestinationPath $zipPath -CompressionLevel Optimal -Force

# Clean up stage
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue

$zipSizeMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Host "`n=== Build Complete! ===" -ForegroundColor Cyan
Write-Host "Artifact: $zipPath ($zipSizeMb MB)" -ForegroundColor Yellow
