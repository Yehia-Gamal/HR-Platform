$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$defineFile = Join-Path $scriptDir "dart_define/staging.json"

if (-not (Test-Path -LiteralPath $defineFile)) {
  Write-Error "Missing Dart define file: $defineFile"
  exit 1
}

$requiredSigningVars = @(
  "RELEASE_STORE_PASSWORD",
  "RELEASE_KEY_PASSWORD"
)

foreach ($name in $requiredSigningVars) {
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
    Write-Error "Release signing variable $name is not set. A debug-signed distribution build is not allowed."
    exit 1
  }
}

Write-Host "Building signed staging APKs with obfuscation and debug symbols..." -ForegroundColor Cyan
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols --dart-define-from-file="$defineFile"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Building signed Android App Bundle..." -ForegroundColor Cyan
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols --dart-define-from-file="$defineFile"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Android artifacts and symbols were built successfully." -ForegroundColor Green
