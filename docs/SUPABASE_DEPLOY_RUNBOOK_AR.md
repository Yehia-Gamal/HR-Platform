# دليل تشغيل Supabase CLI — نشر الباك إند (Migrations + Functions + Secrets)

هذا الدليل يجهّز أوامر النشر بالترتيب الصحيح لمشروع **أحلى شباب Management OS V8**.
شغّل الأوامر من جذر المستودع: `D:\Coder\HR\HR_Platform_2`.

معلومات ثابتة من المشروع:
- `project_id` (محلي): `ahla-shabab-management-os-v8`
- رابط staging المستخدَم في الويب/الموبايل: `https://ujzzvqsodyhnnnpkoaml.supabase.co`
- الـ Project Ref لهذا الرابط: `ujzzvqsodyhnnnpkoaml`
- عدد الـ migrations: 48 ملف (0001 → 0048)
- عدد الـ Edge Functions: 9 (+ `_shared`)

> ملاحظة: تُستخدم `npx supabase ...` لضمان استعمال النسخة المثبّتة محلياً. إن كان لديك
> Supabase CLI مثبَّت عالمياً يمكنك حذف `npx`.

---

## 0) متطلبات مسبقة (مرة واحدة)

```powershell
# التحقق من إصدار الـ CLI (يفضّل 2.x)
npx supabase --version

# تسجيل الدخول (يفتح المتصفح لإنشاء Access Token)
npx supabase login
```

Docker Desktop مطلوب فقط لخطوات **Local** (start / db reset / test db). خطوات الـ **Staging**
عن بُعد لا تحتاج Docker.

---

## 1) التحقق المحلي أولاً (موصى به قبل staging)

يبني قاعدة نظيفة محلياً، يطبّق كل الـ migrations + الـ seed، ثم يشغّل 30 ملف اختبار.

```powershell
# تشغيل الحزمة المحلية (Postgres + Studio + Auth + Storage + Functions)
npx supabase start

# إعادة بناء القاعدة من الصفر: يطبّق migrations/*.sql بالترتيب ثم seed المذكور في config.toml
npx supabase db reset

# تشغيل اختبارات pgTAP في supabase/tests
npx supabase test db
```

وفق `supabase/migrations/README.md`: كرّر `db reset` + `test db` **مرتين محلياً** للتأكد من
الـ idempotency قبل الانتقال إلى staging.

لإيقاف الحزمة المحلية لاحقاً:

```powershell
npx supabase stop
```

---

## 2) الربط بمشروع staging عن بُعد

```powershell
# ربط المستودع بمشروع staging (سيطلب كلمة مرور قاعدة البيانات)
npx supabase link --project-ref ujzzvqsodyhnnnpkoaml
```

للتحقق من الفرق بين migrations المحلية والبعيدة قبل الدفع:

```powershell
npx supabase migration list
```

---

## 3) دفع الـ Migrations إلى staging

```powershell
# يطبّق كل migration لم يُطبَّق بعد على قاعدة staging بالترتيب الرقمي
npx supabase db push
```

إن رغبت بمعاينة ما سيُطبَّق دون تنفيذ:

```powershell
npx supabase db push --dry-run
```

> الـ seed لا يُدفَع تلقائياً مع `db push` (الـ seed يُطبَّق محلياً عبر `db reset`).
> لبذر بيانات الصلاحيات/الأدوار على staging، شغّل ملفي البذر يدوياً عبر psql
> (القيم idempotent):
>
> ```powershell
> # استبدل <DB_URL> برابط اتصال قاعدة staging (من Dashboard → Project Settings → Database)
> psql "<DB_URL>" -f supabase/seed/0001_seed_permissions_roles.sql
> psql "<DB_URL>" -f supabase/seed/0002_seed_used_permissions.sql
> ```

---

## 4) ضبط أسرار الـ Edge Functions (قبل النشر)

الأسرار `SUPABASE_URL` و`SUPABASE_ANON_KEY` و`SUPABASE_SERVICE_ROLE_KEY` **محجوزة**
ويحقنها Supabase تلقائياً — لا تضبطها يدوياً. اضبط فقط الأسرار المخصّصة التالية:

| السر | تستخدمه الدوال | ملاحظة |
|---|---|---|
| `CRON_SECRET` | retention-cleanup, notification-dispatcher, integration-outbox-worker, scheduled-report-runner | توكن حماية استدعاءات الكرون. |
| `LOGIN_HASH_PEPPER` | identifier-sign-in | فلفل تجزئة معرّف الدخول — سر طويل عشوائي. |
| `WEBAUTHN_RP_ID` | webauthn-challenge, verify-attendance-punch, passkey-register | نطاق RP (مثال: `app.example.com` بدون https). |
| `WEBAUTHN_RP_NAME` | webauthn-challenge | اسم العرض لمزوّد الهوية. |
| `ALLOWED_ORIGINS` | كل دوال WebAuthn + `_shared/cors` | قائمة أصول مفصولة بفواصل (CORS). |
| `PUSH_PROVIDER_URL` | notification-dispatcher | نقطة نهاية مزوّد الإشعارات (اختياري). |
| `PUSH_PROVIDER_TOKEN` | notification-dispatcher | توكن مزوّد الإشعارات (اختياري). |
| `INTEGRATION_WEBHOOK_TOKEN` | integration-outbox-worker | توكن الويبهوك للتكاملات الخارجية (اختياري). |
| `APP_INVITE_REDIRECT_URL` | admin-create-employee | رابط إعادة التوجيه بعد قبول دعوة الموظف. |
| `SUPABASE_ENV` | `_shared/cors` | اختياري: `staging` أو `production` لضبط سلوك CORS. |

اضبطها دفعة واحدة (عدّل القيم):

```powershell
npx supabase secrets set `
  CRON_SECRET="<توكن-عشوائي-قوي>" `
  LOGIN_HASH_PEPPER="<سر-عشوائي-طويل>" `
  WEBAUTHN_RP_ID="ujzzvqsodyhnnnpkoaml.supabase.co" `
  WEBAUTHN_RP_NAME="أحلى شباب Management OS" `
  ALLOWED_ORIGINS="http://localhost:5173,https://<نطاق-الويب-الإنتاجي>" `
  APP_INVITE_REDIRECT_URL="https://<نطاق-الويب-الإنتاجي>/auth/setup-password" `
  SUPABASE_ENV="staging" `
  --project-ref ujzzvqsodyhnnnpkoaml
```

الأسرار الاختيارية (اضبطها فقط عند تفعيل الإشعارات/التكاملات):

```powershell
npx supabase secrets set `
  PUSH_PROVIDER_URL="<رابط-المزوّد>" `
  PUSH_PROVIDER_TOKEN="<توكن-المزوّد>" `
  INTEGRATION_WEBHOOK_TOKEN="<توكن-الويبهوك>" `
  --project-ref ujzzvqsodyhnnnpkoaml
```

للتحقق من الأسرار المضبوطة (تظهر الأسماء فقط):

```powershell
npx supabase secrets list --project-ref ujzzvqsodyhnnnpkoaml
```

> لتوليد سر عشوائي قوي في PowerShell:
> ```powershell
> [Convert]::ToBase64String((1..48 | ForEach-Object { Get-Random -Max 256 }))
> ```

---

## 5) نشر الـ Edge Functions إلى staging

إعدادات `verify_jwt` لكل دالة مضبوطة في `supabase/config.toml` (كلها `false`) ويحترمها الـ CLI.

نشر كل الدوال دفعة واحدة:

```powershell
npx supabase functions deploy --project-ref ujzzvqsodyhnnnpkoaml
```

أو نشر كل دالة على حدة (نفس أسماء المجلدات):

```powershell
npx supabase functions deploy verify-attendance-punch   --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions deploy webauthn-challenge         --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions deploy passkey-register           --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions deploy admin-create-employee      --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions deploy identifier-sign-in         --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions deploy scheduled-report-runner    --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions deploy notification-dispatcher    --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions deploy retention-cleanup          --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions deploy integration-outbox-worker  --project-ref ujzzvqsodyhnnnpkoaml
```

> `_shared` ليست دالة مستقلة — إنها كود مشترك تستورده الدوال، ولا تُنشر وحدها.

---

## 6) التحقق بعد النشر

```powershell
# قائمة الدوال المنشورة وحالتها
npx supabase functions list --project-ref ujzzvqsodyhnnnpkoaml

# سجلّات دالة أثناء اختبارها (مثال)
npx supabase functions logs identifier-sign-in --project-ref ujzzvqsodyhnnnpkoaml
```

اختبار سريع من التطبيق:
1. شغّل الويب (`apps/admin_web`) والموبايل (`apps/mobile_flutter/run_staging.ps1`).
2. سجّل الدخول بحساب موجود على staging.
3. تأكد أن الشاشات تُحمّل بيانات حقيقية (موظفون/طلبات/حضور) بدل الفارغ.

إذا ظهرت نتائج فارغة أو أخطاء صلاحيات (RLS)، فغالباً القاعدة تحتاج بيانات بذر/موظفين،
أو المستخدم الحالي بلا Access Context — راجع الخطوة 3 (seed) و`get_my_access_context`.

---

## الترتيب المختصر (نسخة سريعة)

```powershell
npx supabase login
# محلي (اختياري لكن موصى به):
npx supabase start
npx supabase db reset
npx supabase test db
# staging:
npx supabase link --project-ref ujzzvqsodyhnnnpkoaml
npx supabase db push
npx supabase secrets set CRON_SECRET=... LOGIN_HASH_PEPPER=... WEBAUTHN_RP_ID=... WEBAUTHN_RP_NAME=... ALLOWED_ORIGINS=... APP_INVITE_REDIRECT_URL=... --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions deploy --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions list --project-ref ujzzvqsodyhnnnpkoaml
```
