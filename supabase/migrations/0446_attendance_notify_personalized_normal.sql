-- ============================================================================
-- 0446: تخصيص نصوص إشعارات الحضور وتصفية «العاجلة»
-- ============================================================================
-- المشكلتان (طلب المستخدم):
--   1) الإشعارات تظهر بعنوان عام «دخول موظف — تسجيل حضور» بدل نص شخصي
--      باسم الموظف مثل «وصل مصطفى للعمل بالمجمع» و«خرج ياسر من المجمع».
--   2) إشعارات الحضور الروتينية كانت تُنشأ للمدير التنفيذي عبر
--      notify_executive_fullscreen فتُسجَّل بأولوية urgent وتغرق قسم
--      «تنبيهات عاجلة» في الرئيسية — لا فرق بين العاجل والعادي.
--
-- الحل:
--   1) tg_attendance_daily_notify_manager: عنوان شخصي بالاسم الأول
--      (وصل X للعمل بالمجمع / خرج X من المجمع) لإشعاري المدير المباشر
--      والمدير التنفيذي، مع إبقاء التفاصيل (الاسم الكامل والوقت) في المتن.
--   2) إشعار المدير التنفيذي يتحول إلى إشعار عادي (priority='normal')
--      عبر notify_employee بدل قناة full-screen العاجلة — يبقى ظاهراً في
--      قائمة الإشعارات العامة دون أن يحتل قسم العاجلة.
--   3) تخفيض أولوية إشعارات الحضور القائمة المخزنة urgent/high إلى normal
--      وإزالة وسوم full-screen منها حتى تختفي فوراً من قسم «العاجلة».
-- ============================================================================

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) إعادة كتابة تريجر الإشعارات بنصوص شخصية وأولوية عادية للتنفيذي
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.tg_attendance_daily_notify_manager()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_manager uuid;
  v_event text;
  v_time text;
  v_emp_ar text;
  v_first text;
  v_exec_emp uuid;
  v_title text;
  v_body text;
begin
  -- عند إدراج جديد أو تحديث لأوقات الدخول/الخروج
  if tg_op = 'INSERT' then
    if new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  else
    -- UPDATE: فقط عند تغيّر قيمة الدخول/الخروج
    if new.first_check_in is distinct from old.first_check_in and new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is distinct from old.last_check_out and new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  end if;

  select full_name_ar into v_emp_ar from public.employees where id = new.employee_id;

  -- الاسم الأول للعنوان الشخصي (وصل مصطفى…) مع احتياط عند غياب الاسم
  v_first := coalesce(nullif(split_part(coalesce(v_emp_ar, ''), ' ', 1), ''), 'موظف');

  v_time := to_char(
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo',
    'HH24:MI'
  );

  -- 0446: عنوان شخصي باسم الموظف بدل الصيغة العامة
  v_title := case when v_event = 'attendance_check_in'
              then format('وصل %s للعمل بالمجمع', v_first)
              else format('خرج %s من المجمع', v_first) end;
  v_body := format(
    '%s الساعة %s',
    case when v_event = 'attendance_check_in' then 'دخل' else 'انصرف' end,
    v_time
  );

  -- إشعار الموظف نفسه (تأكيد تسجيل الحضور/الانصراف)
  perform public.notify_employee(
    new.employee_id,
    case when v_event = 'attendance_check_in' then 'تم تسجيل حضورك'
         else 'تم تسجيل انصرافك' end,
    format(
      'تم تسجيل %s الساعة %s',
      case when v_event = 'attendance_check_in' then 'حضورك' else 'انصرافك' end,
      v_time
    ),
    'attendance', 'normal', 'attendance_daily', new.id,
    jsonb_build_object(
      'event', v_event,
      'self', true,
      'workDate', new.work_date,
      'time', v_time
    )
  );

  -- إشعار المدير المباشر (أولوية منخفضة — عنوان شخصي 0446)
  select mr.manager_employee_id into v_manager
  from public.manager_relations mr
  where mr.employee_id = new.employee_id
    and mr.relation_type = 'primary'
    and mr.effective_from <= current_date
    and (mr.effective_to is null or mr.effective_to >= current_date)
  order by mr.created_at desc
  limit 1;

  if v_manager is not null then
    perform public.notify_employee(
      v_manager,
      v_title,
      format('%s — %s', coalesce(v_emp_ar, 'موظف'), v_body),
      'attendance', 'low', 'attendance_daily', new.id,
      jsonb_build_object(
        'event', v_event,
        'employeeId', new.employee_id,
        'workDate', new.work_date,
        'managerId', v_manager,
        'time', v_time
      )
    );
  end if;

  -- 0446: إشعار المدير التنفيذي بإشعار «عادي» (لا عاجل ولا full-screen)
  -- حتى لا تغرق إشعارات الحضور الروتينية قسم «تنبيهات عاجلة»؛ تبقى في
  -- قائمة الإشعارات العامة. لا يُشعر التنفيذي عن حضور/انصراف نفسه.
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null and v_exec_emp <> new.employee_id then
    perform public.notify_employee(
      v_exec_emp,
      v_title,
      format('%s — %s', coalesce(v_emp_ar, 'موظف'), v_body),
      'attendance', 'normal', 'attendance_daily', new.id,
      jsonb_build_object(
        'event', v_event,
        'employeeId', new.employee_id,
        'workDate', new.work_date,
        'time', v_time
      )
    );
  end if;

  return new;
end;
$$;

comment on function public.tg_attendance_daily_notify_manager() is
  '0446: يُشعر الموظف نفسه (تأكيد) والمدير المباشر (low) والمدير التنفيذي (normal) بدخول/انصراف أي موظف بعناوين شخصية «وصل فلان للعمل بالمجمع / خرج فلان من المجمع» — إلا التنفيذي نفسه. لا تستخدم قناة full-screen العاجلة لإشعارات الحضور الروتينية.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) تصحيح الإشعارات القائمة: تخفيض أولوية إشعارات الحضور المخزنة كـ
--    urgent/high إلى normal وإزالة وسوم full-screen — تختفي فوراً من
--    قسم «تنبيهات عاجلة» وتظهر ضمن القائمة العامة
-- ═══════════════════════════════════════════════════════════════════════════
update public.notifications
set priority = 'normal',
    metadata = metadata - array['fullScreen', 'executive', 'channel', 'sound']
where category = 'attendance'
  and (priority in ('urgent', 'high') or metadata ? 'fullScreen');

commit;
