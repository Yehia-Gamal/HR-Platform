-- ============================================================================
-- 0470: تعريب رسائل أخطاء بدء/إنهاء المأمورية — كانت إنجليزية فتظهر للموظف
-- كرسالة عامة «حدث خطأ غير متوقع» لأن humanizeError يمرر العربية فقط.
-- استبدال كنوني للدالتين بنفس المنطق مع رسائل عربية واضحة.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.start_my_mission(p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me    uuid := public.current_employee_id();
  v_req   public.requests;
  v_end   date;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_id    uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select * into v_req from public.requests where id = p_request_id;
  if not found then
    raise exception 'لم يتم العثور على طلب المأمورية' using errcode = 'P0002';
  end if;
  if v_req.employee_id <> v_me then
    raise exception 'هذه المأمورية ليست مسندة إليك' using errcode = '42501';
  end if;
  if v_req.request_type not in ('mission','convoy','fundraising') then
    raise exception 'هذا الطلب ليس مأمورية أو تكليفاً' using errcode = '22023';
  end if;
  if v_req.status <> 'approved' then
    raise exception 'يجب اعتماد المأمورية قبل بدئها — راجع الإدارة' using errcode = '22023';
  end if;

  -- 0453: ÙÙØ¹ ØªÙØ±Ø§Ø± Ø§ÙØªÙÙÙØ° ÙÙÙØ³ Ø§ÙØ·ÙØ¨ (ÙÙØ±Ø© ÙØ²Ø¯ÙØ¬Ø©/Ø³Ø¨Ø§Ù)
  if exists (
    select 1 from public.mission_executions
     where request_id = p_request_id
       and status in ('in_progress','completed')
  ) then
    raise exception 'ØªÙ Ø¨Ø¯Ø¡ ÙØ°Ù Ø§ÙÙØ£ÙÙØ±ÙØ© ÙØ³Ø¨ÙÙØ§' using errcode = '22023';
  end if;

  begin
    v_end := (nullif(v_req.payload->>'endDate', ''))::date;
  exception when others then
    v_end := null;
  end;
  if v_end is not null and v_today > v_end then
    raise exception 'ÙØ§ ÙÙÙÙ Ø¨Ø¯Ø¡ Ø§ÙÙØ£ÙÙØ±ÙØ© Ø¨Ø¹Ø¯ Ø§ÙØªÙØ§Ø¡ ÙØ¯ØªÙØ§' using errcode = '22023';
  end if;

  insert into public.mission_executions(request_id, employee_id, status, started_at)
  values (p_request_id, v_me, 'in_progress', now())
  returning id into v_id;

  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.end_my_mission(p_request_id uuid, p_report text, p_outcome text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me      uuid := public.current_employee_id();
  v_exec    public.mission_executions;
  v_minutes integer;
  v_today   date := (now() at time zone 'Africa/Cairo')::date;
  v_cutoff  time;
  v_end_now time := (now() at time zone 'Africa/Cairo')::time;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select * into v_exec from public.mission_executions where request_id = p_request_id;
  if not found then
    raise exception 'لم تبدأ هذه المأمورية بعد' using errcode = 'P0002';
  end if;
  if v_exec.employee_id <> v_me then
    raise exception 'هذه المأمورية ليست مسندة إليك' using errcode = '42501';
  end if;
  if v_exec.status <> 'in_progress' then
    raise exception 'تم إنهاء هذه المأمورية بالفعل' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_report, ''))) < 3 then
    raise exception 'يرجى كتابة تقرير مختصر عن المأمورية (3 أحرف على الأقل)' using errcode = '22023';
  end if;

  v_minutes := greatest(1, round(extract(epoch from (now() - v_exec.started_at)) / 60)::integer);

  update public.mission_executions
     set ended_at         = now(),
         actual_minutes   = v_minutes,
         report           = trim(p_report),
         outcome          = nullif(trim(coalesce(p_outcome, '')), ''),
         status           = 'completed',
         updated_at       = now()
   where id = v_exec.id;

  -- 0450: Ø§ÙÙÙÙ ÙÙØ­ØªØ³Ø¨ Ø­Ø§Ø¶Ø±ÙØ§ ÙÙ ÙØ­Ø¸Ø© Ø¨Ø¯Ø¡ Ø§ÙÙØ£ÙÙØ±ÙØ©Ø ÙØ§ÙØ§ÙØµØ±Ø§Ù ØªÙÙØ§Ø¦Ù
  -- Ø¥Ø°Ø§ ØªÙ Ø§ÙØ¥ÙÙØ§Ø¡ Ø¨Ø¹Ø¯ ÙÙØ§ÙØ© Ø§ÙØ¯ÙØ§ÙØ ÙØ¥ÙØ§ ÙØ¨ÙÙ Ø¨Ø§ÙØªØ¸Ø§Ø± Ø¨ØµÙØ© Ø§ÙØµØ±Ø§Ù Ø¹Ø§Ø¯ÙØ©.
  select coalesce(s.shift_end_time, time '18:00') into v_cutoff
    from public.attendance_settings s where s.singleton_key;
  v_cutoff := coalesce(v_cutoff, time '18:00');

  insert into public.attendance_daily
    (employee_id, work_date, status, first_check_in, last_check_out, work_minutes, updated_at)
  values
    (v_me,
     v_today,
     'present',
     v_exec.started_at,
     case when v_end_now >= v_cutoff then now() end,
     v_minutes,
     now())
  on conflict (employee_id, work_date) do update
    set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
        last_check_out = coalesce(public.attendance_daily.last_check_out, excluded.last_check_out),
        work_minutes   = greatest(public.attendance_daily.work_minutes, excluded.work_minutes),
        status         = case
                           when public.attendance_daily.status in ('absent','missing_checkout','pending')
                             then 'present'
                           else public.attendance_daily.status
                         end,
        updated_at     = now();

  return v_exec.id;
end $function$;