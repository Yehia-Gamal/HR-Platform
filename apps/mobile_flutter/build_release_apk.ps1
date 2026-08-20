$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$defineFile = Join-Path $scriptDir "dart_define/production.json"

if (-not (Test-Path -LiteralPath $defineFile)) {
  Write-Error "Missing Dart define file: $defineFile"
  exit 1
}

if ([string]::IsNullOrWhiteSpace($env:RELEASE_KEYSTORE_PATH)) {
  $env:RELEASE_KEYSTORE_PATH = "release-keystore-v2.jks"
}
if ([string]::IsNullOrWhiteSpace($env:RELEASE_KEY_ALIAS)) {
  $env:RELEASE_KEY_ALIAS = "ahla-shabab"
}
if ([string]::IsNullOrWhiteSpace($env:RELEASE_STORE_PASSWORD)) {
  $env:RELEASE_STORE_PASSWORD = "NmGHpUBEAW6xXYTomd"
}
if ([string]::IsNullOrWhiteSpace($env:RELEASE_KEY_PASSWORD)) {
  $env:RELEASE_KEY_PASSWORD = "NmGHpUBEAW6xXYTomd"
}

Write-Host "Building signed production release APK..." -ForegroundColor Cyan
flutter build apk --release --dart-define-from-file="$defineFile"

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nAPK Built successfully at build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
