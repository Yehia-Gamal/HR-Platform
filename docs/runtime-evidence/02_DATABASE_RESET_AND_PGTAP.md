# 02 — Database Reset & pgTAP (P0.3)

**التاريخ / Date:** 2026-07-15 (إعادة تحقق؛ الأصل 2026-07-14)
**البيئة / Environment:** Windows 10 Pro 19045, Docker Desktop + WSL2, Supabase CLI 2.109.1
**الحالة / Status:** ✅ **PASS** — `db reset` + `test db` ناجحان مرتين متتاليتين من قاعدة فارغة

---

## 1. الأمر والنتيجة النهائية

```bash
npx supabase db reset      # يطبّق 0001→0048 + Seeds
npx supabase test db       # pgTAP
```

| الجولة | Reset Exit | pgTAP Result | تفاصيل |
|---|---:|---|---|
| مبكرة (final3/4) | 0 | ✅ **PASS** | `Files=28, Tests=324` — على حالة 45 migration |
| الحالية (v46_1/2) | 0 | ✅ **PASS** | `Files=29, Tests=333` — على حالة **46 migration / 29 test** |
| **إعادة تحقق 2026-07-15** | 0,0 | ✅ **PASS** | `Files=30, Tests=341` — على حالة **48 migration / 30 test** الحالية (reset ×2 + pgTAP ×2) |

**السجلات:** `_db_reset_v46_1.log`, `_pgtap_v46_2.log` (والمبكرة `_*_final3/4.log`).

```
All tests successful.
Files=29, Tests=333,  ~4 wallclock secs
Result: PASS
```

> **تحديث (46 migration / 29 test):** أُضيف لاحقًا Migration **0046** (كشف Mock GPS + حارس الانتقال
> المستحيل >150كم/س، يُعلّم البصمة `flagged`/`requires_review` بدل الرفض التلقائي — القرار للمشرف عبر
> مسار تصحيحات 0028) وTest **0029** (Break-glass runtime). سبّب 0046 **انحدارًا** في `tests/0001` لأنه
> غيّر توقيع `record_attendance_event` (أضاف `p_is_mock`) بينما 0001 كان يتحقق من التوقيع القديم بـ
> 9 معاملات → `function ... does not exist`. **الإصلاح:** تحديث سلسلة التوقيع في 0001 إلى 10 معاملات
> (لم يُضعَّف التأكيد: لا يزال يثبت أن authenticated لا يستطيع تنفيذ الدالة). بعده: **29/333 PASS**.
> `verify-attendance-punch` مُحدَّث بالفعل ليمرّر `p_is_mock`.

جميع الـ 48 Migration تظهر في `supabase_migrations.schema_migrations` (`max(version)=0048`, 48 صفًا)، وSeed 0001/0002 يعملان دون صلاحيات مفقودة. (أحدث تحقق: 2026-07-15، Files=30/Tests=341 PASS ×2.)

## 2. العيوب الحقيقية المكتشفة والمعالَجة (Runtime defects)

pgTAP كشف عيوبًا تشغيلية حقيقية — عولجت وفق قواعد الخطة (لا تعطيل RLS، لا حذف اختبارات، الإصلاح في Migration جديدة 0041+):

### 2.1 عيب P0: سياسات RLS معطّلة لغياب منح الجداول → Migration 0045
- **الاكتشاف:** `tests/0027` فحص 1 فشل بـ `ERROR: permission denied for table employees` **قبل** تقييم RLS إطلاقًا.
- **السبب الجذري:** PostgreSQL يطبّق منح الجداول (GRANT) أولًا ثم RLS. المخطط يفعّل RLS ويعرّف 190+ سياسة SELECT و87 INSERT و87 UPDATE و77 DELETE للدور `authenticated`، لكن **لم تُمنح صلاحيات الجداول الأساسية لهذا الدور إطلاقًا** — فكانت كل السياسات ميتة عمليًا: الدور المواجه للـ API لا يستطيع قراءة/كتابة أي جدول مباشرة، وكل قراءة كانت تمرّ فقط عبر RPCs من نوع SECURITY DEFINER.
- **الإصلاح (`0045_grant_authenticated_table_privileges.sql`):** منح DML للدور `authenticated` وSELECT للدور `anon` على جداول `public`، مع `alter default privileges` للجداول المستقبلية، ثم **سحب** الكتابة المباشرة عن الجداول الخادمية (`attendance_events`, `passkey_credentials`, `webauthn_challenges`) وحجب الجداول السرية بالكامل (`login_auth_attempts`, `credential_vault`, `password_reset_requests`). RLS يبقى حارس الصفوف.
- **الأمان محفوظ:** `anon` يقرأ فقط وRLS يُرجع صفر صفوف (لا سياسة تستهدف anon)؛ الجداول الخادمية تبقى بلا كتابة مباشرة؛ الكتابة الحساسة تبقى عبر SECURITY DEFINER RPCs.
- **تغطية Regression:** `tests/0027` (23/23)، `tests/0010` و`tests/0012` (غياب صلاحيات Passkey/الحضور)، `tests/0025` (عدم قراءة `login_auth_attempts`) — كلها تنجح معًا.

### 2.2 عيب Runtime: معالج SLA بلا منح service_role → Migration 0043 (جولة سابقة)
- Migration 0026 عملت `revoke ... from public` على `process_request_sla(integer)` دون منح `service_role`. عولج في `0043_grant_service_role_sla_processor.sql`. Regression: `tests/0014` فحص 12.

### 2.3 توافق أدوات pgTAP في 5 ملفات اختبار (لا تغيير أمني)
- `tests/0002`, `0019`, `0023`, `0024`, `0025`: استبدال دوال pgTAP غير المتوفرة في الإصدار المثبّت (`table_has_rls`, `row_security_is_enabled`) بفحوص `pg_class.relrowsecurity`، ولفّ `row_security_active(...)` داخل `ok(...)`. لم يُحذف أي اختبار ولم يُحوَّل إلى Skip.

## 3. الحالة

- Reset قابل للتكرار: ✅ مثبت (مرتان، Exit 0).
- pgTAP: ✅ **Result: PASS مرتين** — Files=30, Tests=341, صفر فشل، صفر Bad plan.
- Persona RLS Runtime: ✅ 23/23 (انظر `03_PERSONA_RLS_MATRIX.md`).
- بوابة قاعدة البيانات المحلية: **مغلقة بنجاح.**

## 4. إعادة التحقق على الحالة الكاملة (48 migration / 30 test) — ✅ نُفِّذت

بعد جولة الـ29 المعتمدة أعلاه أُضيف إلى المصدر ثم أُعيد التحقق منه حيًّا (2026-07-15):

- **Migration 0047** (`scheduling_leave_accrual_and_cron`): عمود `monthly_accrual_units`
  على `leave_types`، ودالة `run_monthly_leave_accrual` (service_role فقط، idempotent عبر
  `source_key`، لا تتجاوز `max_days_per_year`)، وتفعيل `pg_cron` وجدولة المهام الأربع
  (SLA كل 10د، الاستحقاق أول الشهر 00:30، تنظيف الاحتفاظ يوميًا 02:00، طابور التقارير كل 15د)
  مع حارس `pg_available_extensions` يتجاوز الجدولة بأمان إن غاب `pg_cron` محليًا دون كسر الترحيل.
- **Migration 0048** (`pgcrypto_search_path_for_digest`): إعادة تعريف `decision_content_hash`
  بـ `search_path = public, extensions` لحلّ `digest` أينما ثُبّتت الإضافة — يمنع فشل
  `function digest(text, unknown) does not exist` عند `db push` على Supabase المُدار.
- **Test 0030** (`leave_accrual_scheduling`): 8 فحوصات تغطّي 0047 — وجود العمود والدالة،
  حصر التنفيذ على `service_role` (ورفض `authenticated`)، صحة وحدات القيد (2.5)، idempotency عند
  إعادة التشغيل لنفس الشهر (لا قيد مكرر)، والحد السنوي (لا يتجاوز 30 بعد 12 شهرًا).

**النتيجة الفعلية بعد إعادة التشغيل** (انظر `FINAL_READINESS_REPORT_AR.md` §6.1):
`db reset` ×2 (Exit 0، pg_cron جُدول 4 مهام) + `test db` ×2 → **Files=30, Tests=341, Result: PASS**،
شاملاً 0029 (Break-glass) و0030 (الاستحقاق). البوابة **مغلقة على الحالة الكاملة 48/30**.

> ملاحظة: الجدولان في القسمين 1 و3 أعلاه يذكران `Files=30, Tests=341` وهو الرقم النهائي الصحيح
> بعد دمج 0029/0030؛ السجلات المبكرة (`_pgtap_v8.log` = 29 ملفًا) تمثل حالة وسيطة سابقة فقط.
