-- =====================================================================
-- V25 - إصلاح حلقة الرنين المتكرر لطلبات الموقع العاجل
-- ---------------------------------------------------------------------
-- المشكلة: هاتف الموظف يستمر بالرنين والطلب مراراً حتى بعد قبول/إرسال/
-- رفض الطلب. الأسباب في الخادم:
--
-- 1) upsert_my_push_token كان يعيد جدولة push job لأي طلب موقعه في
--    ('pending','accepted','active') - أي حتى بعد أن ردّ الموظف فعلاً
--    (accepted/active) - عند كل إطلاق تطبيق أو تجديد رمز FCM.
--    -> يقتصر الاسترداد الآن على الطلبات التي ما زالت 'pending' فعلاً.
--
-- 2) نافذة جلسة القبول في respond_live_location_request كانت تساوي
--    duration_minutes (دقيقة واحدة لأوضاع اللقطة). إذا تأخر GPS أكثر من
--    دقيقة يفشل submit_live_location_point ويبقى الطلب 'active' - فيكون
--    (1) سبباً في إعادة الرنين إلى الأبد.
--    -> الحد الأدنى للنافذة 5 دقائق مهما كان duration_minutes.
--
-- 3) trigger جديد يلغي أي push job (queued/failed/processing) تابع لإشعار
--    طلب موقع ما إن لم يعد الطلب pending - يقطع إعادة المحاولات والاسترداد.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) الاسترداد للطلبات المعلّقة فقط
-- ---------------------------------------------------------------------
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

    -- One physical FCM token must never remain active for two signed-in users.
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
    on conflict (user_id, fcm_token) where fcm_token is not null
    do update set
      endpoint = excluded.endpoint,
      p256dh_key = excluded.p256dh_key,
      auth_key = excluded.auth_key,
      platform = excluded.platform,
      is_active = true,
      last_used_at = v_now,
      updated_at = v_now;

    -- A request may have been created before the first successful token upsert.
    -- Insert its missing push job, or retry a previously terminal token_missing
    -- job, while never redelivering a job already marked sent.
    --
    -- V25: فقط الطلبات التي ما زالت 'pending' - قبول/رفض/إكمال الطلب يوقف
    -- أي إعادة إرسال لاحقة (كانت 'accepted'/'active' تسبب الرنين المتكرر
    -- بعد أن ردّ الموظف بالفعل).
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

revoke all on function public.upsert_my_push_token(text, text)
  from public, anon, authenticated;
grant execute on function public.upsert_my_push_token(text, text)
  to authenticated;

-- ---------------------------------------------------------------------
-- 2) نافذة قبول سخية: 5 دقائق على الأقل لإرسال نقطة الموقع بعد القبول
-- ---------------------------------------------------------------------
create or replace function public.respond_live_location_request(
  p_request_id uuid,
  p_accept boolean
)
  returns public.live_location_requests
  language plpgsql
  security definer
  set search_path = public, pg_temp
  as $$
  declare
    v_me uuid := public.current_employee_id();
    v_row public.live_location_requests;
    v_window_minutes integer;
  begin
    select * into v_row
    from public.live_location_requests
    where id = p_request_id
    for update;

    if not found or v_row.employee_id is distinct from v_me then
      raise exception 'request not found' using errcode = 'P0002';
    end if;
    if v_row.status <> 'pending' or v_row.expires_at <= now() then
      raise exception 'request is no longer pending' using errcode = '22023';
    end if;

    if p_accept then
      -- V25: لا تقل نافذة الجلسة عن 5 دقائق حتى لو كان duration_minutes=1
      -- (لقطة). كانت الدقيقة الواحدة تفشل الإرسال عند تأخر GPS وتبقي الطلب
      -- active، فتستمر إعادة إرسال الإشعار إلى الأبد.
      v_window_minutes := greatest(coalesce(v_row.duration_minutes, 5), 5);
      update public.live_location_requests
      set status = 'active',
          responded_at = now(),
          starts_at = now(),
          expires_at = now() + make_interval(mins => v_window_minutes)
      where id = p_request_id
      returning * into v_row;
    else
      update public.live_location_requests
      set status = 'rejected',
          responded_at = now()
      where id = p_request_id
      returning * into v_row;
    end if;

    perform public.log_audit_event(
      case when p_accept then 'live_location.accepted' else 'live_location.rejected' end,
      'security',
      'info',
      'live_location_requests',
      v_row.id,
      'رد على طلب موقع',
      null,
      jsonb_build_object('accepted', p_accept)
    );
    return v_row;
  end;
  $$;

revoke execute on function public.respond_live_location_request(uuid, boolean)
  from public;
grant execute on function public.respond_live_location_request(uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------------
-- 3) إلغاء push jobs لطلب لم يعد pending - يقطع إعادة المحاولات
-- ---------------------------------------------------------------------
create or replace function public.cancel_stale_location_push_jobs()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status <> 'pending' then
    update public.notification_jobs j
    set status = 'cancelled',
        last_error = 'request_no_longer_pending',
        locked_at = null,
        locked_by = null
    from public.notifications n
    where n.id = j.notification_id
      and n.entity_type = 'live_location_request'
      and n.entity_id = new.id
      and j.channel = 'push'
      and j.status in ('queued', 'failed', 'processing');
  end if;
  return new;
end;
$$;

revoke all on function public.cancel_stale_location_push_jobs()
  from public, anon, authenticated;

drop trigger if exists trg_location_req_cancel_stale_push_jobs
  on public.live_location_requests;
create trigger trg_location_req_cancel_stale_push_jobs
after update of status on public.live_location_requests
for each row execute function public.cancel_stale_location_push_jobs();

notify pgrst, 'reload schema';