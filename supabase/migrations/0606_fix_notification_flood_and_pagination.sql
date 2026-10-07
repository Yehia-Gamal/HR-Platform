-- =====================================================================
-- 0606_fix_notification_flood_and_pagination.sql
-- 1. منع الفيضان المتكرر لإشعارات الغرامات وتصعيد التأخير كل 10 دقائق
-- 2. إيقاف إرسال إشعار "تم إيقافك عن العمل" للمديرين والتنفيذيين
-- 3. رفع سقف الإشعارات من 200 إلى 1000 ودعم التصفح بالأوفست (Pagination)
-- =====================================================================

begin;

-- ─── 1) تحديث get_my_notifications لدعم التصفح وسقف حتى 1000 ──────────────
drop function if exists public.get_my_notifications(integer);
drop function if exists public.get_my_notifications(integer, integer);

create or replace function public.get_my_notifications(
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', n.id,
    'title', n.title,
    'body', n.body,
    'category', n.category,
    'priority', n.priority,
    'actionUrl', n.action_url,
    'entityType', n.entity_type,
    'entityId', n.entity_id,
    'metadata', coalesce(n.metadata, '{}'::jsonb),
    'isRead', n.is_read,
    'createdAt', n.created_at
  ) order by n.created_at desc), '[]'::jsonb)
  from (
    select * from public.notifications
    where recipient_user_id = auth.uid() and is_archived = false
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 1000))
    offset greatest(0, coalesce(p_offset, 0))
  ) n;
$$;

revoke all on function public.get_my_notifications(integer, integer) from public;
grant execute on function public.get_my_notifications(integer, integer) to authenticated;

-- توافق مع العقد القديم (0004/0011): overload بارمتر واحد يعيد النتيجة نفسها
-- بصفحة أولى — بدونه تحذف has_function(array['integer']) ويكسر اختباري
-- 0004 (notification inbox exists) و0011 (owner-scoped mobile notifications).
create or replace function public.get_my_notifications(p_limit integer)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select public.get_my_notifications(p_limit, 0);
$$;

revoke all on function public.get_my_notifications(integer) from public;
grant execute on function public.get_my_notifications(integer) to authenticated;

-- ─── 2) ضبط دالة إشعار أصحاب الشأن بالغرامات لمنع الإزعاج المتكرر ───────────
create or replace function public._notify_instant_penalty_stakeholders(
  p_employee_id uuid,
  p_title text,
  p_body text,
  p_entity_type text,
  p_entity_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_mgr_id uuid;
  v_emp_name text;
  v_mgr_title text;
  v_mgr_body text;
  v_is_suspension boolean;
begin
  select full_name_ar into v_emp_name
    from public.employees
   where id = p_employee_id;

  v_is_suspension := (p_entity_type = 'instant_penalty_suspended' or p_title like '%إيقاف%');

  -- 1) إشعار الموظف نفسه بالصيغة المباشرة
  perform public.notify_employee(
    p_employee_id,
    p_title,
    p_body,
    'system',
    'urgent',
    p_entity_type,
    p_entity_id,
    p_metadata
  );

  -- 2) إشعار المدير المباشر بصيغة واضحة تحدد اسم الموظف (لا صيغة "تم إيقافك أنت")
  select mr.manager_employee_id into v_mgr_id
    from public.manager_relations mr
    join public.employees m on m.id = mr.manager_employee_id
   where mr.employee_id = p_employee_id
     and mr.effective_from <= current_date
     and (mr.effective_to is null or mr.effective_to >= current_date)
     and m.is_active = true
   order by case mr.relation_type
              when 'primary' then 1 when 'functional' then 2 else 3
            end
   limit 1;

  if v_mgr_id is not null and v_mgr_id <> p_employee_id then
    v_mgr_title := case
      when v_is_suspension then '🚫 إشعار إيقاف موظف عن العمل'
      else '⚠️ غرامة تأخير لموظف بفريقك'
    end;

    v_mgr_body := case
      when v_is_suspension then
        'إشعار إداري: تم إيقاف ' || coalesce(v_emp_name, 'موظف') || ' عن العمل مؤقتاً لعدم سداد غرامة التأخير (500 ج.م).'
      else
        'إشعار لفريقك: تم تسجيل/تحديث غرامة تأخير على ' || coalesce(v_emp_name, 'موظف') || '.'
    end;

    perform public.notify_employee(
      v_mgr_id,
      v_mgr_title,
      v_mgr_body,
      'attendance',
      'high',
      p_entity_type,
      p_entity_id,
      jsonb_build_object(
        'employeeId', p_employee_id::text,
        'employeeName', v_emp_name,
        'penaltyId', p_entity_id::text
      ) || coalesce(p_metadata, '{}'::jsonb)
    );
  end if;

  -- 3) إشعار مسؤولي الموارد البشرية فقط عند الإيقاف عن العمل الحرج (وليس في كل تأخير روتيني)
  if v_is_suspension then
    perform public.notify_employees_with_permission(
      'payroll.run.manage',
      '🚫 إشعار إيقاف موظف عن العمل',
      'تم إيقاف الموظف ' || coalesce(v_emp_name, 'موظف') || ' وغلق حسابه لعدم سداد الغرامة لليوم الثالث.',
      'system',
      'urgent',
      p_entity_type,
      p_entity_id,
      p_metadata,
      p_employee_id
    );
  end if;
end;
$$;

revoke all on function public._notify_instant_penalty_stakeholders(uuid, text, text, text, uuid, jsonb) from public, anon;
grant execute on function public._notify_instant_penalty_stakeholders(uuid, text, text, text, uuid, jsonb) to authenticated, service_role;

-- ─── 3) تحديث generate_instant_penalty لمنع تكرار الإشعار ما لم تتغير شريحة الغرامة ──
create or replace function public.generate_instant_penalty(
  p_employee_id uuid,
  p_work_date date,
  p_late_minutes integer,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
  v_emp record;
  v_amount numeric(10,2);
  v_daily_rate numeric(10,2);
  v_default_notes text;
  v_row record;
  v_exempt jsonb;
  v_effective_late_minutes integer;
  v_emp_name text;
begin
  -- 1) فحص الإعفاء الدائم أو اليومي
  v_exempt := public.is_employee_exempt_from_instant_penalty(p_employee_id, p_work_date);
  if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
    return jsonb_build_object(
      'success', false,
      'isExempt', true,
      'reason', coalesce(v_exempt->>'reason', 'معفى من الغرامات'),
      'amount', 0
    );
  end if;

  -- 2) جلب بيانات الموظف
  select e.id, e.full_name_ar, e.salary, e.base_salary, e.is_active, e.status
    into v_emp
    from public.employees e
   where e.id = p_employee_id;

  if v_emp.id is null then
    raise exception 'الموظف غير موجود' using errcode = 'P0002';
  end if;

  v_emp_name := v_emp.full_name_ar;

  -- 3) حساب مدة التأخير الفعالة (بحد أقصى ساعتان = 120 دقيقة)
  v_effective_late_minutes := least(120, greatest(0, coalesce(p_late_minutes, 0)));

  -- احتساب قيمة الغرامة بحسب الشرائح المعتمدة:
  -- من 1 إلى 15 دقيقة: سماح (0 ج.م)
  -- من 16 إلى 30 دقيقة: 50 ج.م
  -- من 31 إلى 60 دقيقة: 100 ج.م
  -- أكثر من 60 دقيقة: 150 ج.م
  if v_effective_late_minutes <= 15 then
    return jsonb_build_object(
      'success', false,
      'isGrace', true,
      'message', 'التأخير ضمن فترة السماح (15 دقيقة)',
      'amount', 0
    );
  elsif v_effective_late_minutes <= 30 then
    v_amount := 50.00;
  elsif v_effective_late_minutes <= 60 then
    v_amount := 100.00;
  else
    v_amount := 150.00;
  end if;

  v_default_notes := coalesce(
    trim(p_notes),
    'غرامة تأخير حضور (' || v_effective_late_minutes || ' دقيقة) ليوم ' || p_work_date::text
  );

  -- 4) محاولة إدراج الغرامة إن لم تكن موجودة
  insert into public.instant_attendance_penalties (
    employee_id, work_date, late_minutes, original_amount, current_amount,
    currency, status, notes
  ) values (
    p_employee_id, p_work_date, v_effective_late_minutes, v_amount, v_amount,
    'EGP', 'pending_payment', v_default_notes
  )
  on conflict (employee_id, work_date) do nothing
  returning * into v_row;

  -- 5) إذا كانت مسجلة مسبقاً لهذا اليوم:
  if v_row.id is null then
    select * into v_row
      from public.instant_attendance_penalties
     where employee_id = p_employee_id and work_date = p_work_date;

    -- إذا كانت لا تزال قيد السداد وانتقلت لشريحة مالية أعلى: يتم التصعيد والإشعار
    if v_row.status = 'pending_payment' and v_amount > v_row.current_amount then
      update public.instant_attendance_penalties
         set late_minutes = v_effective_late_minutes,
             original_amount = v_amount,
             current_amount = v_amount,
             notes = v_default_notes,
             updated_at = now()
       where id = v_row.id
      returning * into v_row;

      perform public._notify_instant_penalty_stakeholders(
        p_employee_id,
        '⚠️ تصعيد غرامة تأخير الحضور',
        'تزايد التأخير إلى ' || case when v_effective_late_minutes >= 120 then 'ساعتين (الحد الأقصى)' else v_effective_late_minutes || ' دقيقة' end || ' — تم تحديث الغرامة إلى ' || v_amount || ' ج.م.',
        'instant_penalty',
        v_row.id,
        jsonb_build_object(
          'employeeId', p_employee_id::text,
          'penaltyId', v_row.id::text,
          'lateMinutes', v_effective_late_minutes,
          'originalAmount', v_amount,
          'currentAmount', v_amount,
          'channel', 'instant_penalty',
          'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
        )
      );
    -- أما إذا كان المبلغ هو نفسه والتأخير فقط زاد بضع دقائق دون الانتقال لشريحة جديدة:
    -- تحديث الدقائق والملاحظات في السجل بصمت دون إرسال إشعار مزعج
    elsif v_row.status = 'pending_payment' and v_effective_late_minutes > coalesce(v_row.late_minutes, 0) then
      update public.instant_attendance_penalties
         set late_minutes = v_effective_late_minutes,
             notes = v_default_notes,
             updated_at = now()
       where id = v_row.id
      returning * into v_row;
    end if;

    return jsonb_build_object(
      'id', v_row.id,
      'alreadyExists', true,
      'amount', v_row.current_amount,
      'status', v_row.status,
      'lateMinutes', v_row.late_minutes,
      'message', 'تم تحديث السجل اليومي للغرامة'
    );
  end if;

  -- 6) إشعار أصحاب الشأن عند إنشاء الغرامة لأول مرة فقط
  perform public._notify_instant_penalty_stakeholders(
    p_employee_id,
    '⚠️ تسجيل غرامة تأخير حضور فورية',
    'تم تسجيل غرامة تأخير حضور قدرها ' || v_amount || ' ج.م عن تأخير ' || v_effective_late_minutes || ' دقيقة ليوم ' || p_work_date::text || '. يُرجى السداد خلال يومين.',
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', p_employee_id::text,
      'penaltyId', v_row.id::text,
      'lateMinutes', v_effective_late_minutes,
      'originalAmount', v_amount,
      'currentAmount', v_amount,
      'channel', 'instant_penalty',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  return jsonb_build_object(
    'id', v_row.id,
    'created', true,
    'amount', v_row.current_amount,
    'status', v_row.status,
    'lateMinutes', v_row.late_minutes
  );
end;
$$;

revoke all on function public.generate_instant_penalty(uuid, date, integer, text) from public, anon;
grant execute on function public.generate_instant_penalty(uuid, date, integer, text) to authenticated, service_role;

commit;
