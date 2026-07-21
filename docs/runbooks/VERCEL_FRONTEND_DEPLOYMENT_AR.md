# نشر واجهة admin_web على Vercel

هذا الدليل يغطّي رفع واجهة React فقط. الـbackend (Supabase) يُنشَر عبر
`scripts/deploy-staging.sh` كما في `STAGING_DEPLOYMENT_RUNBOOK_AR.md`. أكمِل الـbackend أولاً.

## المتطلّبات المسبقة
- مشروع Supabase (Staging) منشور فعلاً، ولديك: `Project URL` و`publishable/anon key`.
- الـrepo مرفوع على GitHub/GitLab متاح لـVercel.
- ملف `vercel.json` موجود بجذر المشروع (مضمّن في الـrepo).

## 1. استيراد المشروع في Vercel
1. Vercel → Add New → Project → استورد الـrepo.
2. **Root Directory**: اتركه على جذر الـrepo (`./`) — الـmonorepo يُبنى من الجذر، و`vercel.json` يوجّه الإخراج إلى `apps/admin_web/dist`.
3. Framework Preset: `Other` (الإعدادات مأخوذة من `vercel.json`، لا تتركه يخمّن Vite).
4. لا تُعدّل Build/Output يدويًا — `vercel.json` يضبط:
   - Build: `npm run build`
   - Output: `apps/admin_web/dist`
   - Install: `npm ci`

## 2. متغيرات البيئة (Environment Variables)
أضِف هذه في Project → Settings → Environment Variables (Production + Preview):

| المتغير | القيمة |
|---|---|
| `VITE_SUPABASE_URL` | `https://<PROJECT_REF>.supabase.co` |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | المفتاح العام (publishable/anon) — **ليس** service_role |
| `VITE_ENABLE_DEV_MOCKS` | `false` |
| `VITE_APP_VERSION` | `0.10.0` |
| `VITE_APP_BUILD` | `10` |
| `VITE_APP_ENVIRONMENT` | `staging` (أو `production` لاحقًا) |

> لا تضع `SERVICE_ROLE_KEY` أو `CRON_SECRET` هنا إطلاقًا — تلك أسرار خادمية تبقى في Supabase Secrets.

## 3. ربط CORS و WebAuthn origins مع Supabase
بعد أول نشر ستحصل على نطاق Vercel (مثل `https://ahla-hr-staging.vercel.app`).
حدّث أسرار Supabase Edge Functions لتقبل هذا النطاق:

- `ALLOWED_ORIGINS` = نطاق Vercel (وأي نطاق مخصّص تضيفه لاحقًا، مفصولة بفواصل).
- `WEBAUTHN_RP_ID` = المضيف بلا بروتوكول (مثل `ahla-hr-staging.vercel.app`).
- `ALLOWED_ORIGINS` يجب أن يطابق الأصل تمامًا وإلا تُرفض نداءات الـEdge Functions (CORS) وتسجيل Passkey.

اضبطها من Supabase Dashboard → Edge Functions → Secrets، ثم أعِد نشر الوظائف إن لزم.

### روابط تفعيل الموظفين وإعادة تعيين كلمة المرور

اضبط كذلك القيم التالية حتى لا تعود رسائل الموظفين إلى `localhost`:

- Supabase Dashboard → Authentication → URL Configuration:
  - **Site URL** = `https://ahla-shabab-management-os.vercel.app`
  - **Redirect URLs** تتضمن `https://ahla-shabab-management-os.vercel.app/**`
- Supabase Dashboard → Edge Functions → Secrets:
  - `APP_INVITE_REDIRECT_URL` = `https://ahla-shabab-management-os.vercel.app/auth/setup-password`

صفحة `/auth/setup-password` تستقبل جلسة الاسترداد، تحذف رموزها من شريط
العنوان فورًا، وتسمح للموظف بتعيين كلمة المرور ثم تُبطل جلسات الاسترداد.

## 4. النطاق المخصّص (اختياري)
عند إضافة نطاق مخصّص في Vercel، كرّر تحديث `ALLOWED_ORIGINS` و`WEBAUTHN_RP_ID` بالنطاق الجديد.

## 5. التحقق بعد النشر
1. افتح نطاق Vercel وسجّل الدخول بحساب Persona تجريبي.
2. **اختبر الـSPA rewrites**: انتقل إلى مسار داخلي (مثل `/hr/employees`) ثم **حدّث الصفحة (F5)** — يجب أن تُحمَّل بلا 404 (تؤكد أن الـrewrites في `vercel.json` تعمل).
3. **اختبر الـRPC/CORS**: نفّذ عملية تكتب لـSupabase (مثل اتخاذ قرار على طلب) وتأكّد من نجاحها بلا خطأ CORS في الـConsole.
4. إن ظهر خطأ CORS/Passkey → راجع تطابق `ALLOWED_ORIGINS`/`WEBAUTHN_RP_ID` مع نطاق Vercel.
5. أنشئ موظفًا تجريبيًا، وافتح دعوة التفعيل وتأكد أنها تنتقل إلى
   `/auth/setup-password` ولا تحتوي على `localhost`.

## ملاحظة حوكمة الإصدار
لا يُحوّل إلى Production قبل اجتياز بوابات Staging في `STAGING_DEPLOYMENT_RUNBOOK_AR.md`
(migrations، RLS personas، WebAuthn على هاتف فعلي، GPS/الكاميرا، النسخ الاحتياطي والاستعادة، وإغلاق أي P0/P1).
