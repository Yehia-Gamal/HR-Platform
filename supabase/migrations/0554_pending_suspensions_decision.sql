-- ═══════════════════════════════════════════════════════════════
-- 0554: لوحة قرار التعليق — تكملة قرار المالك في 0550
--
-- منذ 0550 لا يعلّق الكرون أحداً: الصفوف المستحقة تبقى `doubled` ويُسجَّل
-- instant_penalty.suspension_pending. لكن لم يكن في الواجهة ما يعرضها أو
-- ينفّذ القرار. هذه الـmigration تضيف:
--
--   • get_pending_suspensions()            — المستحقون الآن (غير معفيين، نشطون).
--   • suspend_employee_for_penalty(id, سبب) — تنفيذ قرار بشري لغرامة واحدة،
--     بنفس خطوات مرحلة التعليق في auto_escalate_instant_penalties (0550)
--     وإشعاراتها — بما فيها إشعار الفريق كاملاً (قرار المالك: يبقى للجميع).
--
-- الصلاحية = شرط حارسَي employees (0004) و profiles (0289) حرفياً، وهو نفس
-- v_can_suspend في 0550: full-access، أو update_sensitive و profiles.manage معاً.
-- السبب إلزامي ويُحفظ في حدث التدقيق.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ═══════════════════════════════════════════════
-- 1. المستحقون للتعليق
-- ═══════════════════════════════════════════════
create or replace function public.get_pending_suspensions()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;
  if not (public.current_is_full_access()
          or (public.has_permission('people.employee.update_sensitive')
              and public.has_permission('profiles.manage'))) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'penaltyId',      t.id,
        'employeeId',     t.employee_id,
        'employeeName',   t.employee_name,
        'employeeCode',   t.employee_code,
        'departmentName', t.department_name,
        'workDate',       t.work_date,
        'amount',         t.current_amount,
        'daysOverdue',    t.days_overdue
      )
      order by t.work_date asc, t.id
    )
    from (
      select p.id,
             p.employee_id,
             e.full_name_ar          as employee_name,
             e.employee_code,
             d.name                  as department_name,
             p.work_date,
             p.current_amount,
             (v_today - p.work_date) as days_overdue
        from public.instant_attendance_penalties p
        join public.employees e on e.id = p.employee_id
        left join public.departments d on d.id = e.department_id
       where p.status = 'doubled'
         and p.escalation_level = 'doubled'
         and p.work_date < v_today - 1
         and e.status = 'active'
         and coalesce(
               (public.is_employee_exempt_from_instant_penalty(p.employee_id, p.work_date)->>'isExempt')::boolean,
               false) = false
    ) t
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_pending_suspensions() from public, anon;
grant execute on function public.get_pending_suspensions() to authenticated, service_role;

-- ═══════════════════════════════════════════════
-- 2. تنفيذ قرار التعليق لغرامة واحدة
-- ═══════════════════════════════════════════════
create or replace function public.suspend_employee_for_penalty(
  p_penalty_id uuid,
  p_reason     text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_today      date := (now() at time zone 'Africa/Cairo')::date;
  v_rec        public.instant_attendance_penalties;
  v_emp_name   text;
  v_emp_status text;
  v_exempt     jsonb;
begin
  if auth.uid() is null then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;
  if not (public.current_is_full_access()
          or (public.has_permission('people.employee.update_sensitive')
              and public.has_permission('profiles.manage'))) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'سبب القرار مطلوب (3 أحرف على الأقل)' using errcode = '22023';
  end if;

  select * into v_rec
    from public.instant_attendance_penalties
   where id = p_penalty_id
   for update;
  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;
  if v_rec.status <> 'doubled' or v_rec.escalation_level <> 'doubled' then
    raise exception 'الغرامة ليست في مرحلة التعليق (الحالة الحالية: %)', v_rec.status using errcode = '22023';
  end if;
  if v_rec.work_date >= v_today - 1 then
    raise exception 'لم تنقضِ مهلة السداد بعد' using errcode = '22023';
  end if;

  -- إعادة فحص الإعفاء لحظة القرار (مأمورية/إجازة/عطلة سُجِّلت بعد المضاعفة)
  v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
  if coalesce((v_exempt->>'isExempt')::boolean, false) then
    raise exception 'الموظف معفى من هذه الغرامة: %', coalesce(v_exempt->>'reason', '—') using errcode = '22023';
  end if;

  select full_name_ar, status into v_emp_name, v_emp_status
    from public.employees where id = v_rec.employee_id;
  if v_emp_status is distinct from 'active' then
    raise exception 'لا يمكن تعليق موظف حالته %', coalesce(v_emp_status, 'غير معروفة') using errcode = '22023';
  end if;

  -- ── نفس خطوات مرحلة التعليق في 0550 ──
  update public.instant_attendance_penalties
     set status = 'suspended',
         escalation_level = 'suspended',
         suspended_at = now(),
         updated_at = now()
   where id = v_rec.id;

  update public.employees
     set status = 'suspended',
         is_active = false,
         updated_at = now()
   where id = v_rec.employee_id;

  update public.profiles
     set status = 'suspended',
         updated_at = now()
   where employee_id = v_rec.employee_id;

  perform public.log_audit_event(
    'instant_penalty.suspended', 'security', 'critical',
    'instant_attendance_penalties', v_rec.id,
    'تعليق موظف عن العمل بقرار بشري: ' || coalesce(v_emp_name, 'موظف'),
    trim(p_reason),
    jsonb_build_object('employeeId', v_rec.employee_id,
                       'amount', v_rec.current_amount,
                       'decidedByEmployeeId', public.current_employee_id(),
                       'manualDecision', true)
  );

  perform public._notify_instant_penalty_stakeholders(
    v_rec.employee_id,
    '🚫 إيقاف عن العمل وغلق الحساب',
    'تم إيقافك عن العمل وغلق حسابك على السيستم لعدم سداد غرامة الـ 500 ج.م. يجب التوجه للـ HR وسداد المبلغ لإعادة فتح الحساب ومباشرة العمل.',
    'instant_penalty_suspended',
    v_rec.id,
    jsonb_build_object(
      'employeeId', v_rec.employee_id::text,
      'amount', v_rec.current_amount,
      'channel', 'instant_penalty_suspended',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  -- إشعار الفريق كاملاً (قرار المالك 2026-09-24: يبقى للجميع)
  perform public.notify_employee(
    e.id,
    '🚫 إشعار إيقاف موظف عن العمل',
    'إشعار للفريق: تم إيقاف ' || coalesce(v_emp_name, 'أحد الموظفين') || ' عن العمل مؤقتاً وغلق حسابه على السيستم لعدم سداد غرامة التأخير (500 ج.م) حتى يتم السداد للـ HR وإزالة الغرامة وعودته لمباشرة العمل.',
    'system',
    'urgent',
    'instant_penalty_suspended',
    v_rec.id,
    jsonb_build_object(
      'employeeId', v_rec.employee_id::text,
      'suspendedEmployeeName', v_emp_name,
      'amount', 500,
      'channel', 'team_suspension_broadcast'
    )
  )
    from public.employees e
   where e.is_active = true
     and coalesce(e.is_deleted, false) = false
     and e.id <> v_rec.employee_id;

  return jsonb_build_object(
    'success', true,
    'penaltyId', v_rec.id,
    'employeeId', v_rec.employee_id
  );
end;
$$;

revoke all on function public.suspend_employee_for_penalty(uuid, text) from public, anon;
grant execute on function public.suspend_employee_for_penalty(uuid, text) to authenticated, service_role;

commit;
