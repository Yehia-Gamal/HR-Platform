-- ============================================================================
-- 0493: فهرس فريد على fcm_token وحده لمطابقة ON CONFLICT (fcm_token)
-- ============================================================================
-- upsert_my_push_token الكنوني (0483) يستخدم `on conflict (fcm_token)`،
-- لكن الفهرس الوحيد الموجود (من 0033/0067) كان مركّباً على (user_id, fcm_token)
-- أو أُلغي بسبب `if not exists` بنفس الاسم. النتيجة: أي إدراج عبر upsert_my_push_token
-- يفشل في زمن التشغيل بـ "no unique or exclusion constraint matching ON CONFLICT".
--
-- هنا ننشئ فهرساً فريداً على العمود fcm_token وحده (حيث القيمة غير فارغة) ليطابق
-- عقدة ON CONFLICT، مع تصفية أي تكرارات سابقة بأمان.
-- ============================================================================

-- 1) تصفية التكرارات (نُبقي الأحدث inactive فقط في حال وجود تكرارات قديمة).
update public.push_subscriptions
set is_active = false,
    updated_at = now()
where fcm_token is not null
  and id not in (
    select distinct on (fcm_token) id
    from public.push_subscriptions
    where fcm_token is not null
    order by fcm_token, last_used_at desc nulls last, created_at desc, id
  );

-- 2) الفهرس الفريد على fcm_token وحده (غير جزئي: الحقول NULL تتسامح معها
--    PostgreSQL بلا قيود، والـ ON CONFLICT (fcm_token) في الدوال الحية يطابق
--    هذا الفهرس تماماً دون الحاجة إلى WHERE).
create unique index if not exists ux_push_subscriptions_fcm_token
  on public.push_subscriptions (fcm_token);

-- 3) الفهرس المركّب القديم (user_id, fcm_token) لم يعد مطابقاً لأي ON CONFLICT
--    في الدوال الحية (كلها تعتمد على fcm_token وحده) — نزيله لتجنب الالتباس
--    المستقبلي مع عقدة ON CONFLICT (user_id, fcm_token) القديمة.
drop index if exists public.ux_push_subscriptions_fcm;