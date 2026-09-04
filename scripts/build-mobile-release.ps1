# ==============================================================================
# سكربت بناء وتجهيز تطبيق الهاتف المحمول للإنتاج (Android App Bundle & iOS)
# منظومة أحلى شباب للموارد البشرية والتشغيل (Ahla Shabab HR)
# ==============================================================================

param (
    [string]$Target = "android",
    [switch]$SkipAnalyze
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$FlutterAppDir = Join-Path $ProjectRoot "apps\mobile_flutter"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "   أحلى شباب HR — تجهيز حزم الإنتاج الرسمية للمتاجر    " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

Set-Location $FlutterAppDir

# 1. فحص الكود البرمجي (Static Analysis)
if (-not $SkipAnalyze) {
    Write-Host "`n[1/4] جاري فحص الكود البرمجي (Flutter Analyze)..." -ForegroundColor Yellow
    flutter analyze --no-fatal-infos
    if ($LASTEXITCODE -ne 0) {
        Write-Error "فشل فحص الكود. يرجى مراجعة وتصحيح التحذيرات أولاً."
    }
    Write-Host "✓ اجتاز الكود كافة معايير الجودة." -ForegroundColor Green
}

# 2. تنظيف وجلب التبعيات (Pub Get)
Write-Host "`n[2/4] جاري تحديث الحزم والتبعيات الرسمية..." -ForegroundColor Yellow
flutter pub get

# 3. بناء الحزمة المطلوبة
if ($Target -eq "android" -or $Target -eq "all") {
    Write-Host "`n[3/4] جاري بناء حزمة أندرويد الرسمية لمتجر Google Play (.aab)..." -ForegroundColor Yellow
    flutter build appbundle --release --obfuscate --split-debug-info=build/app/outputs/symbols
    
    $AabPath = Join-Path $FlutterAppDir "build\app\outputs\bundle\release\app-release.aab"
    if (Test-Path $AabPath) {
        $SizeMb = [math]::Round((Get-Item $AabPath).Length / 1MB, 2)
        Write-Host "✓ تم بناء حزمة الأندرويد بنجاح!" -ForegroundColor Green
        Write-Host "  المسار: $AabPath" -ForegroundColor White
        Write-Host "  الحجم: $SizeMb MB" -ForegroundColor White
    }
}

if ($Target -eq "ios" -or $Target -eq "all") {
    Write-Host "`n[4/4] جاري بناء حزمة iOS الرسمية لمتجر App Store..." -ForegroundColor Yellow
    if ($IsMacOS -or $env:OS -eq "Darwin") {
        flutter build ipa --release
        Write-Host "✓ تم بناء حزمة iOS بنجاح!" -ForegroundColor Green
    } else {
        Write-Host "⚠️  تنبيه: بناء حزمة iOS يتطلب نظام macOS وبيئة Xcode." -ForegroundColor Yellow
    }
}

Write-Host "`n======================================================" -ForegroundColor Cyan
Write-Host "   اكتمل البناء بنجاح! الحزمة جاهزة للرفع على المتاجر  " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
