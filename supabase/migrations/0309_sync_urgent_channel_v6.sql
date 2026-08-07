-- =====================================================================
-- 0309: مزامنة قناة الإشعار العاجلة للموقع الحي مع معرّف القناة الفعلي v6.
-- =====================================================================
-- خلفية: migration 0096 يكتب channel='urgent_location_v4' في metadata
--   لكل إشعار live_location_request. لكن الكود الأصلي (UrgentNotificationManager
--   + firebaseMessaging default channel + Dart PushService) يستخدم v6 منذ
--   يناير 2026. التطابق ضروري حتى يعرف FCM أيَّ قناة يعرض عليها الإشعار عندما
--   يكون التطبيق مغلقاً — دون ذلك Android 12+ يسقط الإشعار من قناة مجهولة.
-- idempotent: CREATE OR REPLACE + UPDATE محدود بالصفوف التي تحتاج تعديلاً.
-- =====================================================================

-- 1. حدّث trigger التطبيع: يستبدل v4 بـ v6 فقط، ولن يكسر صفوفاً قديمة.
create or replace function public.normalize_live_location_notification()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_request_id text;
  v_deep_link text;
begin
  if new.entity_type is distinct from 'live_location_request' then
    return new;
  end if;
  v_request_id := coalesce(new.metadata->>'requestId', new.entity_id::text);
  if nullif(v_request_id, '') is null then
    return new;
  end if;
  v_deep_link := 'https://ahla-shabab-management-os.vercel.app/action/live_location_request/' || v_request_id;
  new.action_url := v_deep_link;
  new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_build_object(
    'fullScreen', true,
    'kind', 'live_location_request',
    'requestId', v_request_id,
    'entityId', v_request_id,
    'channel', 'urgent_location_v6',
    'sound', 'urgent_notification',
    'deepLink', v_deep_link
  );
  return new;
end;
$$;

-- 2. الزناد موجود من 0096 — لا حاجة لإعادة إنشائه.

-- 3. صحّح الصفوف الموجودة (فقط تلك التي تحمل قناة v4).
update public.notifications
   set metadata = metadata || jsonb_build_object('channel', 'urgent_location_v6')
 where entity_type = 'live_location_request'
   and coalesce(metadata->>'channel', 'urgent_location_v4') = 'urgent_location_v4';

notify pgrst, 'reload schema';
