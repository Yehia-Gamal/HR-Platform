# بناء حزمة Android (APK) متصلة بـ Supabase (Staging) للتجربة على الأجهزة.
# الناتج: build/app/outputs/flutter-apk/app-release.apk
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$defineFile = Join-Path $scriptDir "dart_define/staging.json"

if (-not (Test-Path $defineFile)) {
  Write-Error "لم يتم العثور على $defineFile — انسخ dart_define/staging.example.json واملأ القيم."
  exit 1
}

$requiredSigningVars = @(
  "RELEASE_STORE_PASSWORD",
  "RELEASE_KEY_PASSWORD"
)
foreach ($name in $requiredSigningVars) {
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
    Write-Error "متغير توقيع الإصدار $name غير مضبوط. لن يتم إنشاء APK بتوقيع debug للتوزيع."
    exit 1
  }
}

Write-Host "بناء APKs (staging) مع obfuscation وملفات الرموز..." -ForegroundColor Cyan
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols --dart-define-from-file="$defineFile"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "بناء Android App Bundle..." -ForegroundColor Cyan
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols --dart-define-from-file="$defineFile"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "تم. APKs في build/app/outputs/flutter-apk وAAB في build/app/outputs/bundle/release والرموز في build/symbols." -ForegroundColor Green
