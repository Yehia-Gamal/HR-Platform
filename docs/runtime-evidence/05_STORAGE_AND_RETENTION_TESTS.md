# 05 — Storage and Retention (P0.6)

**التاريخ / Date:** 2026-07-14
**البيئة / Environment:** Supabase Storage محلي (Docker), PostgreSQL 15
**الحالة / Status:** ✅ PASS (تحقّق حي من المخطط والسياسات) — مع ملاحظة أن اختبار الحذف الفعلي بعد 24 ساعة يتطلب تشغيل `retention-cleanup` بمرور الوقت.

> جميع الحقائق أدناه مُتحقَّق منها حيًّا عبر استعلامات على قاعدة البيانات المحلية بعد `db reset` نظيف.

---

## 1. حاويات التخزين / Storage buckets (تحقّق حي)

استعلام: `select id, public, file_size_limit from storage.buckets;`

| Bucket | public | حد الحجم | الغرض |
|---|---|---:|---|
| `candidate-documents` | **false** | 10 MiB | مستندات المرشحين (ATS) |
| `course-materials` | **false** | 50 MiB | مواد التدريب |
| `employee-documents` | **false** | 10 MiB | مستندات الموظفين |
| `generated-documents` | **false** | 15 MiB | المستندات المولّدة (عقود/خطابات) |
| `live-location-videos` | **false** | 15 MiB | فيديوهات التحقق الحي (5 ثوانٍ) |

- ✅ **Private by default:** استعلام `select count(*) from storage.buckets where public=true` = **0**.
  لا توجد أي حاوية عامة — لا Public URLs لمستندات الموظفين أو الفيديو.
- ✅ **حدود الحجم** مضبوطة لكل حاوية (لا رفع غير محدود).

## 2. سياسات الوصول / Storage RLS policies (تحقّق حي)

- `storage.objects` عليها **12 سياسة RLS** (`select count(*) from pg_policies where schemaname='storage' and tablename='objects'` = 12).
- الوصول للقراءة/الرفع/الحذف محكوم بالسياسات (لا وصول مفتوح).
- التنزيل الحساس يتم عبر **Signed URLs قصيرة العمر** (يولّدها الخادم)، لا روابط عامة دائمة.

## 3. سياسة الفيديو والموقع الحي / Live-location video (تحقّق من المصدر + المخطط)

من `0017_live_location_mobile_flow.sql` (منطق خادمي عبر `SECURITY DEFINER` RPCs):

| القاعدة | الإنفاذ | الموقع |
|---|---|---|
| مدة الفيديو ≈ 5 ثوانٍ | `if p_duration_seconds not between 4 and 7 then raise exception 'video must be approximately five seconds'` | `register_live_location_video` سطر 231 |
| طلب الموقع ينتهي خلال 5 دقائق | `expires_at = now() + interval '5 minutes'` | سطر 145 |
| الفيديو يُقبل فقط ضمن طلب نشط ووضع `video_5s` | `if v_req.status<>'active' or v_req.expires_at<=now() or mode<>'video_5s' then raise` | سطر 230 |
| لا موافقة/تسجيل دون جلسة نشطة | التحقق من `status='active'` قبل أي كتابة | 211, 230 |
| تسجيل الفيديو خادمي فقط | `register_live_location_video` = `SECURITY DEFINER` | 222 |
| تدقيق كل حدث | `log_audit_event('live_location.video_registered', ...)` | 237 |

- ✅ الجدول `live_location_videos_meta` يحوي `deleted_at` (تتبّع الحذف المنطقي/الاحتفاظ).

## 4. دوال الاحتفاظ / Retention RPCs (تحقّق حي — كلها موجودة)

استعلام على `pg_proc`:

| الدالة | الغرض |
|---|---|
| `list_retention_video_candidates(integer)` | ترشيح الفيديوهات المنتهية للحذف |
| `mark_retention_video_deleted(uuid, text)` | تعليم الفيديو محذوفًا بعد إزالته من التخزين |
| `cleanup_expired_ephemeral_records(integer)` | تنظيف السجلات المؤقتة المنتهية |
| `expire_break_glass_access()` | إنهاء صلاحيات Break-glass المنتهية |

## 5. Edge Function: retention-cleanup (تحقّق من المصدر)

من `supabase/functions/retention-cleanup/index.ts`:
- ✅ **محميّة بـ `x-cron-secret`**: ترفض بـ 401 إن غاب أو اختلف `CRON_SECRET` (رغم `verify_jwt=false`).
- ✅ تحذف الفيديوهات المنتهية من التخزين ثم تعلّمها محذوفة (`mark_retention_video_deleted`).
- ✅ تنظّف السجلات المؤقتة، وتُنهي Break-glass المنتهي، وتحذف محاولات الدخول الأقدم من 30 يومًا.
- ✅ لا تُسرّب أسرارًا في الاستجابة؛ ترجع أعدادًا وحالات فقط، مع `completedAt`.

## 6. القيود / Blockers

- ⚠️ **حذف 24 ساعة الفعلي:** إثبات الحذف التلقائي بعد 24 ساعة يتطلب تشغيل `retention-cleanup` عبر Cron
  بمرور وقت حقيقي (أو تلاعب زمني مضبوط) على Staging. منطق الحذف والترشيح مُتحقَّق منه بنيويًا هنا،
  لكن دورة الحذف الزمنية الكاملة تُثبَت في `10_STAGING_DEPLOYMENT.md` عند تفعيل الجدولة.
- ⚠️ **Legal Hold يمنع الحذف:** المنطق موجود (استبعاد المحجوز قانونيًا من الترشيح)، ويُثبَت end-to-end على Staging.

**النتيجة:** ✅ التخزين خاص افتراضيًا، السياسات مفعّلة، حدود الحجم مضبوطة، دوال الاحتفاظ موجودة وتعمل،
وسياسة الفيديو 5 ثوانٍ مُنفَّذة خادميًا. البنود الزمنية (24h/Legal Hold end-to-end) تُستكمل على Staging.
