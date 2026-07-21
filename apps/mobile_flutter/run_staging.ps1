# تشغيل تطبيق Flutter متصلاً بمشروع Supabase (Staging).
# الاستخدام:  ./run_staging.ps1            (تشغيل على الجهاز/المحاكي الافتراضي)
#            ./run_staging.ps1 -d chrome   (تشغيل على متصفح للمعاينة)
# يقرأ الإعدادات من dart_define/staging.json عبر --dart-define-from-file.

param(
  [string]$Device = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$defineFile = Join-Path $scriptDir "dart_define/staging.json"

if (-not (Test-Path $defineFile)) {
  Write-Error "لم يتم العثور على $defineFile — انسخ dart_define/staging.example.json إلى staging.json واملأ القيم."
  exit 1
}

$deviceArgs = @()
if ($Device -ne "") { $deviceArgs = @("-d", $Device) }

Write-Host "تشغيل Flutter متصلاً بـ Supabase (staging)..." -ForegroundColor Cyan
flutter run --dart-define-from-file="$defineFile" @deviceArgs
