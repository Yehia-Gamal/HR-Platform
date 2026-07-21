<#
  fix_staging_backend.ps1
  إصلاح باك إند staging ليطابق مجلد HR_Platform_2:
    1) يتحقق أنك في المجلد الصحيح (به الدوال الصحيحة)
    2) يربط المشروع
    3) يعاين ثم يدفع الـ migrations
    4) يعيد نشر الدوال الـ 9 الصحيحة
    5) (اختياري) يحذف الدوال القديمة الزائدة عبر -CleanupStale
    6) يعرض النتيجة

  الاستخدام:
    ./fix_staging_backend.ps1                 # الإصلاح الكامل الآمن
    ./fix_staging_backend.ps1 -CleanupStale   # + حذف الدوال القديمة
    ./fix_staging_backend.ps1 -SkipDbPush     # نشر الدوال فقط دون لمس القاعدة

  ملاحظة: لا يشغّل أي أمر يمسح بيانات (db reset) إطلاقاً. لو تعذّر db push بسبب
  تعارض تاريخ الهجرات، يتوقف ويطبع الإرشاد بدل المخاطرة بالبيانات.
#>

param(
  [string]$ProjectRef = "ujzzvqsodyhnnnpkoaml",
  [string]$AppUrl = "https://ahla-shabab-management-os.vercel.app",
  [switch]$CleanupStale,
  [switch]$SkipDbPush
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  ✔ $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }

# --- 1) التحقق من المجلد الصحيح ------------------------------------------------
Step "التحقق من أن هذا هو مجلد المصدر الصحيح (HR_Platform_2)"

$expected = @(
  'admin-create-employee','identifier-sign-in','integration-outbox-worker',
  'notification-dispatcher','passkey-register','retention-cleanup',
  'scheduled-report-runner','verify-attendance-punch','webauthn-challenge'
)
$funcDir = Join-Path $root "supabase/functions"
if (-not (Test-Path $funcDir)) {
  Write-Error "لا يوجد supabase/functions هنا. شغّل السكربت من جذر مجلد HR_Platform_2."
  exit 1
}
$present = Get-ChildItem $funcDir -Directory | Select-Object -ExpandProperty Name
$missing = $expected | Where-Object { $_ -notin $present }
if ($missing.Count -gt 0) {
  Write-Error ("هذا ليس المجلد الصحيح — دوال مفقودة: " + ($missing -join ", ") +
    "`nتأكد أنك في D:\Coder\HR\HR_Platform_2 وليس HR_Platform.")
  exit 1
}
Ok "الدوال الصحيحة موجودة (9)."

# --- تحقق من وجود Supabase CLI -------------------------------------------------
try { npx supabase --version | Out-Null; Ok "Supabase CLI متاح." }
catch { Write-Error "Supabase CLI غير متاح. ثبّته أو تأكد من npx."; exit 1 }

# --- 2) الربط -----------------------------------------------------------------
Step "ربط المشروع ($ProjectRef)"
try {
  npx supabase link --project-ref $ProjectRef
  Ok "تم الربط."
} catch {
  Warn "قد يكون المشروع مربوطاً مسبقاً — سيتم المتابعة."
}

# --- 3) دفع الـ migrations -----------------------------------------------------
if (-not $SkipDbPush) {
  Step "معاينة الـ migrations (dry-run)"
  npx supabase db push --dry-run

  Step "دفع الـ migrations"
  try {
    npx supabase db push
    Ok "تم دفع الـ migrations."
  } catch {
    Warn "فشل db push — غالباً تعارض تاريخ الهجرات لأن staging عليه نسخة أقدم."
    Warn "لا تعمل db reset إن كانت staging تحوي بيانات مهمة."
    Warn "شغّل:  npx supabase migration list --project-ref $ProjectRef"
    Warn "وأرسل المخرجات لمطابقة التاريخ يدوياً (migration repair) دون فقد بيانات."
    Write-Host "توقف عند دفع القاعدة. الدوال لم تُنشر بعد." -ForegroundColor Red
    exit 2
  }
} else {
  Warn "تم تخطي db push بطلبك (-SkipDbPush)."
}

# --- 4) نشر الدوال ------------------------------------------------------------
Step "إعادة نشر الدوال الصحيحة الـ 9"
npx supabase functions deploy --project-ref $ProjectRef
Ok "تم نشر الدوال (بما فيها identifier-sign-in و admin-create-employee)."

# --- 4b) إصلاح روابط تفعيل الحساب / استعادة كلمة المرور ------------------------
# سبب مشكلة "This site can't be reached" عند فتح رابط الإيميل: كان Site URL على
# staging = localhost:3000. نضبط الآن سرّ إعادة التوجيه للدالة + عنوان الموقع.
Step "ضبط رابط إعادة التوجيه للإيميلات ($AppUrl)"
try {
  npx supabase secrets set "APP_INVITE_REDIRECT_URL=$AppUrl/" --project-ref $ProjectRef
  Ok "تم ضبط APP_INVITE_REDIRECT_URL."
} catch {
  Warn "تعذّر ضبط السرّ عبر CLI — اضبطه يدوياً من Dashboard > Edge Functions > Secrets."
}
Warn "مهم: افتح Supabase Dashboard > Authentication > URL Configuration واضبط:"
Warn "   Site URL = $AppUrl"
Warn "   Redirect URLs: أضف  $AppUrl/**  و  http://localhost:5173/**"
Warn "   (لا يمكن للـ CLI تعديل Site URL على المشروع المُدار؛ يلزم من اللوحة)."

# --- 5) تنظيف الدوال القديمة (اختياري) ----------------------------------------
if ($CleanupStale) {
  Step "حذف الدوال القديمة الزائدة"
  $stale = @('resolve-login-identifier','admin-create-user',
             'complete-initial-password','process-request-sla')
  foreach ($fn in $stale) {
    try {
      npx supabase functions delete $fn --project-ref $ProjectRef
      Ok "حُذفت: $fn"
    } catch {
      Warn "تعذّر حذف $fn (قد تكون غير موجودة) — تجاهُل."
    }
  }
} else {
  Warn "لم تُحذف الدوال القديمة. أضف -CleanupStale للتنظيف بعد التأكد."
}

# --- 6) التحقق النهائي --------------------------------------------------------
Step "قائمة الدوال بعد النشر"
npx supabase functions list --project-ref $ProjectRef

Write-Host "`nتم. جرّب تسجيل الدخول من الويب/الموبايل — يجب أن يعمل الآن." -ForegroundColor Green
