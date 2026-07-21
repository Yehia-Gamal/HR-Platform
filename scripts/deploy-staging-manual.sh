#!/usr/bin/env bash
# نشر يدوي إلى Supabase Staging — يشغّله المطوّر على جهازه بعد `npx supabase login`.
# نسخة أمتن من deploy-staging.sh: تفحص تسجيل الدخول، وتتحمّل فشل npm ci (مرآة معطّلة)،
# وتطبع رسائل عربية واضحة عند كل خطوة. لا يحتوي أي سر — تُمرَّر المتغيرات من البيئة.
set -euo pipefail

: "${CONFIRM_STAGING:?اضبط CONFIRM_STAGING=YES بعد تأكيد أن هذه ليست بيئة إنتاج}"
: "${STAGING_PROJECT_REF:?اضبط STAGING_PROJECT_REF (مثل ujzzvqsodyhnnnpkoaml)}"
: "${VITE_SUPABASE_URL:?اضبط VITE_SUPABASE_URL}"
: "${VITE_SUPABASE_PUBLISHABLE_KEY:?اضبط VITE_SUPABASE_PUBLISHABLE_KEY}"
VITE_APP_VERSION="${VITE_APP_VERSION:-0.10.0}"
VITE_APP_BUILD="${VITE_APP_BUILD:-10}"
VITE_APP_ENVIRONMENT="${VITE_APP_ENVIRONMENT:-staging}"
export VITE_APP_VERSION VITE_APP_BUILD VITE_APP_ENVIRONMENT

if [[ "$CONFIRM_STAGING" != "YES" ]]; then
  echo "الرفض: يجب أن يساوي CONFIRM_STAGING القيمة YES." >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> [1/6] التحقق من تسجيل الدخول إلى Supabase"
if ! npx supabase projects list >/dev/null 2>&1; then
  echo "لست مسجّلًا في Supabase CLI. نفّذ أولًا: npx supabase login" >&2
  exit 3
fi

echo "==> [2/6] تثبيت الاعتماديات"
if ! npm ci 2>/dev/null; then
  echo "    npm ci فشل (غالبًا مرآة الحزم في package-lock). التبديل إلى npm install."
  npm install
fi

echo "==> [3/6] بوابة الجودة (typecheck + test + build + dart + foundation + secrets)"
npm run check:all

echo "==> [4/6] ربط المشروع ودفع الـmigrations"
npx supabase link --project-ref "$STAGING_PROJECT_REF"
npx supabase db push

echo "==> [5/6] نشر Edge Functions (تُستثنى _shared)"
for directory in supabase/functions/*; do
  [[ -d "$directory" ]] || continue
  name="$(basename "$directory")"
  [[ "$name" == "_shared" ]] && continue
  echo "    - نشر $name"
  npx supabase functions deploy "$name" --project-ref "$STAGING_PROJECT_REF"
done

echo "==> [6/6] بناء الواجهة (بلا mocks)"
VITE_ENABLE_DEV_MOCKS=false npm run build

cat <<'DONE'

اكتمل نشر مصدر Staging. الخطوات المتبقية (يدويًا في Supabase Dashboard):
  1) اضبط أسرار Edge Functions: SUPABASE_SERVICE_ROLE_KEY, ALLOWED_ORIGINS,
     CRON_SECRET, WEBAUTHN_RP_ID, WEBAUTHN_RP_NAME, وموصل Push.
  2) جدولة Cron: notification-dispatcher و integration-outbox-worker (كل 1–5 دقائق)،
     scheduled-report-runner (يوميًا)، retention-cleanup (كل ساعة) — بترويسة x-cron-secret.
  3) أنشئ حساب مستخدم Persona واحدًا على الأقل لتسجيل الدخول.
  4) شغّل scripts/edge-smoke-tests.sh للتحقق من الوظائف.
DONE
