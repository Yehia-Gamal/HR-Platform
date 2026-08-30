-- ============================================================================
-- 0494: إعادة بناء upsert_my_push_token الكنوني (V25)
-- ============================================================================
-- Migration 0421 أضاف منطق "استرداد" للطلبات المعلّقة بعد تسجيل التوكن:
-- أي طلب live_location_request ما زال pending مع push job فاشل/ملغى يجب إعادة
-- جدولته (queued) عند نجاح upsert_my_push_token. إعادة البناء الكنونية في 0483
-- أبقت البنية البسيطة وأسقطت حلقة الاسترداد، فتوقف اختبار 0421-1 ("pending
-- request push job is recovered to queued").
--
-- هنا نعيد النسخة الكاملة الكنونية مع «استرداد» الطلبات المعلّقة، مع ضبط
-- ON CONFLICT (fcm_token) ليطابق الفهرس الفريد الجديد 0493.
-- ============================================================================

create or replace function public.upsert_my_push_token(
  p_fcm_token text,
  p_platform text default 'android'
)
  returns void
  language plpgsql
  security definer
  set search_path = public, pg_temp
  as $$
  declare
    v_user_id uuid := auth.uid();
    v_token text := trim(p_fcm_token);
    v_now timestamptz := now();
    v_recovered integer := 0;
  begin
    if v_user_id is null then
      raise exception 'unauthorized' using errcode = '42501';
    end if;
    if length(v_token) < 16 then
      raise exception 'token_too_short' using errcode = '22023';
    end if;
    if p_platform not in ('android', 'ios', 'web') then
      raise exception 'invalid_platform' using errcode = '22023';
    end if;

    -- لا يبقى التوكن الفيزيائي الواحد نشطاً لمستخدمَين في الوقت نفسه.
    update public.push_subscriptions
    set is_active = false,
        updated_at = v_now
    where fcm_token = v_token
      and user_id <> v_user_id
      and is_active;

    insert into public.push_subscriptions(
      user_id,
      endpoint,
      p256dh_key,
      auth_key,
      fcm_token,
      platform,
      is_active,
      last_used_at,
      created_by
    ) values (
      v_user_id,
      'fcm://' || v_token,
      '-',
      '-',
      v_token,
      p_platform,
      true,
      v_now,
      v_user_id
    )
    on conflict (fcm_token) do update set
      user_id = excluded.user_id,
      endpoint = excluded.endpoint,
      p256dh_key = excluded.p256dh_key,
      auth_key = excluded.auth_key,
      platform = excluded.platform,
      is_active = true,
      last_used_at = v_now,
      updated_at = v_now;

    -- طلب قد يكون أُنشئ قبل أول تسجيل ناجح للتوكن: نُدخل push job الناقص،
    -- أو نعيد محاولة job فاشل/ملغى سابق، دون إعادة تسليم job ذهب sent.
    insert into public.notification_jobs(
      notification_id,
      recipient_user_id,
      channel,
      status,
      available_at,
      attempts,
      idempotency_key
    )
    select
      n.id,
      n.recipient_user_id,
      'push',
      'queued',
      v_now,
      0,
      n.id::text || ':push'
    from public.notifications n
    join public.live_location_requests r
      on r.id = n.entity_id
    where n.recipient_user_id = v_user_id
      and n.entity_type = 'live_location_request'
      and r.status = 'pending'
      and (r.expires_at is null or r.expires_at > v_now)
    on conflict (idempotency_key)
    do update set
      status = 'queued',
      available_at = v_now,
      attempts = 0,
      last_error = null,
      locked_at = null,
      locked_by = null
    where public.notification_jobs.status in ('failed', 'cancelled');

    get diagnostics v_recovered = row_count;
    if v_recovered > 0 then
      perform public.nudge_notification_dispatcher();
    end if;
  end;
  $$;

revoke all on function public.upsert_my_push_token(text, text) from public, anon;
grant execute on function public.upsert_my_push_token(text, text) to authenticated;