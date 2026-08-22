$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$defineFile = Join-Path $scriptDir "dart_define/production.json"
$signingFile = Join-Path $scriptDir "dart_define/signing.local.json"

if (-not (Test-Path -LiteralPath $defineFile)) {
  Write-Error "Missing Dart define file: $defineFile"
  exit 1
}

# كلمات المرور لا تُكتب في المستودع أبداً — تُقرأ من متغيرات البيئة
# (RELEASE_STORE_PASSWORD / RELEASE_KEY_PASSWORD / RELEASE_KEYSTORE_PATH / RELEASE_KEY_ALIAS)
# أو من ملف dart_define/signing.local.json المحلي المتجاهَل في git.
if ([string]::IsNullOrWhiteSpace($env:RELEASE_STORE_PASSWORD) -and (Test-Path -LiteralPath $signingFile)) {
  $signing = Get-Content -LiteralPath $signingFile -Raw | ConvertFrom-Json
  if ([string]::IsNullOrWhiteSpace($env:RELEASE_KEYSTORE_PATH) -and $signing.keystorePath) { $env:RELEASE_KEYSTORE_PATH = $signing.keystorePath }
  if ([string]::IsNullOrWhiteSpace($env:RELEASE_KEY_ALIAS) -and $signing.keyAlias) { $env:RELEASE_KEY_ALIAS = $signing.keyAlias }
  if ($signing.storePassword) { $env:RELEASE_STORE_PASSWORD = $signing.storePassword }
  if ($signing.keyPassword) { $env:RELEASE_KEY_PASSWORD = $signing.keyPassword }
}

if ([string]::IsNullOrWhiteSpace($env:RELEASE_KEYSTORE_PATH)) {
  $env:RELEASE_KEYSTORE_PATH = "release-keystore-v2.jks"
}
if ([string]::IsNullOrWhiteSpace($env:RELEASE_KEY_ALIAS)) {
  $env:RELEASE_KEY_ALIAS = "ahla-shabab"
}
if ([string]::IsNullOrWhiteSpace($env:RELEASE_STORE_PASSWORD) -or [string]::IsNullOrWhiteSpace($env:RELEASE_KEY_PASSWORD)) {
  Write-Error ("Missing release signing credentials. Set RELEASE_STORE_PASSWORD / RELEASE_KEY_PASSWORD env vars, " +
    "or create dart_define/signing.local.json (template: signing.local.example.json).")
  exit 1
}

Write-Host "Building signed production release APK..." -ForegroundColor Cyan
flutter build apk --release --dart-define-from-file="$defineFile"

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nAPK Built successfully at build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
