-- ═══════════════════════════════════════════════════════════════
-- 0550: المضاعفة تلقائية، التعليق قرار بشري (قرار المالك 2026-09-23)
--
-- الخلل: auto_escalate_instant_penalties لا يستدعيها إلا pg_cron ('0 5 * * *') —
-- زر «افحص الآن» (trigger_check_instant_penalties_now) يستدعي auto_generate فقط.
-- والكرون بلا JWT: current_is_full_access() = false، فحارس employees (0004، بلا
-- أي استثناء لـ service_role) وحارس profiles (0289) يرفضان تغيير status. أول
-- صف يبلغ مرحلة التعليق يرفع 42501، فيلتقطه `exception when others → return 0`
-- ويُلغي الدورة كاملة — **بما فيها كل المضاعفات** — ويسجّل
-- instant_penalty.escalation_failed فقط. أي: في كل يوم يوجد فيه مستحق للتعليق
-- لا تتضاعف أي غرامة، ولا يُعلَّق أحد.
--
-- الإصلاح (استبدال كنوني من 0534 — إضافتان فقط):
--   • v_can_suspend = نفس شرط الحارسين حرفياً.
--   • إن لم يتحقق: سجّل instant_penalty.suspension_pending (severity=warning)
--     واترك الصف `doubled`. المضاعفة والإلغاءات بالإعفاء تُحفظ فعلاً.
--   • المستخدم المخوَّل الذي يستدعي الدالة يحصل على التعليق الكامل كما صُمِّم.
--
-- ملاحظة: log_audit_event (0011) تحوّل أي severity غير صالحة إلى 'info'، فأحداث
-- المضاعفة المسجّلة بـ 'high' تُحفظ فعلاً بـ 'info'. لذا نستخدم 'warning' هنا.
-- ═══════════════════════════════════════════════════════════════

begin;

create or replace function public.auto_escalate_instant_penalties()
returns integer
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_today date := ((now() at time zone 'Africa/Cairo')::date);
  v_rec record;
  v_escalated integer := 0;
  v_emp_name text;
  v_exempt jsonb;
  v_pending integer := 0;
  -- 0550: التعليق يكتب employees.status و profiles.status؛ حارساهما (0004 و 0289)
  -- يسمحان بذلك لـ full-access، أو لمن يملك update_sensitive و profiles.manage معاً.
  -- نطابق شرطهما حرفياً حتى لا تصطدم الدالة بهما أبداً.
  v_can_suspend boolean := public.current_is_full_access()
                           or (public.has_permission('people.employee.update_sensitive')
                               and public.has_permission('profiles.manage'));
begin
  -- الكرون (auth.uid() is null) مسموح. استدعاء يدوي يتطلب صلاحية.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('payroll.run.manage')) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- ═══ المرحلة 1: مضاعفة الغرامات المتأخرة (pending_payment من أمس فأقدم) ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status = 'pending_payment'
       and p.escalation_level = 'initial'
       and p.work_date < v_today
  loop
    -- فحص الإعفاء قبل المضاعفة
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي عند فحص المضاعفة: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;
      continue;
    end if;

    update public.instant_attendance_penalties
       set status = 'doubled',
           escalation_level = 'doubled',
           current_amount = 500.00,
           updated_at = now()
     where id = v_rec.id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.doubled', 'financial', 'high',
      'instant_attendance_penalties', v_rec.id,
      'مضاعفة غرامة فورية: ' || coalesce(v_emp_name, 'موظف') || ' — 500 ج.م',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'originalAmount', v_rec.original_amount)
    );

    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '🔴 مضاعفة غرامة تأخير — 500 ج.م',
      coalesce(v_emp_name, 'الموظف') || ' لم يسدد غرامة التأخير في الموعد. تمت مضاعفة الغرامة إلى 500 ج.م. يجب السداد فوراً وإلا سيتم تعليقه عن العمل.',
      'instant_penalty_doubled',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'originalAmount', v_rec.original_amount,
        'newAmount', 500,
        'channel', 'instant_penalty_doubled',
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );

    v_escalated := v_escalated + 1;
  end loop;

  -- ═══ المرحلة 2: اليوم الثالث — غلق السيستم وإيقاف الموظف عن العمل وإشعار كامل الفريق ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status = 'doubled'
       and p.escalation_level = 'doubled'
       and p.work_date < v_today - 1
  loop
    -- فحص الإعفاء قبل التعليق
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي عند فحص الإيقاف: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;

      -- رفع أي تعليق إن وجد
      update public.employees set is_active = true where id = v_rec.employee_id;
      continue;
    end if;

    -- 0550: التعليق قرار بشري. في الكرون (بلا JWT) أو لمن لا يملك تغيير الحالة
    -- كان حارسا employees/profiles يرفضان التحديث، فيلتقط `when others` الخطأ
    -- ويُلغي الدورة كاملة — بما فيها المضاعفات — ويُرجع 0 بصمت.
    -- الآن: نسجّل الاستحقاق ونترك الصف `doubled` حتى يقرر إنسان مخوَّل.
    if not v_can_suspend then
      perform public.log_audit_event(
        'instant_penalty.suspension_pending', 'operations', 'warning',
        'instant_attendance_penalties', v_rec.id,
        'موظف مستحق للتعليق — بانتظار قرار بشري',
        null,
        jsonb_build_object('employeeId', v_rec.employee_id,
                           'amount', v_rec.current_amount,
                           'workDate', v_rec.work_date)
      );
      v_pending := v_pending + 1;
      continue;
    end if;

    -- 1) تحديث سجل الغرامة
    update public.instant_attendance_penalties
       set status = 'suspended',
           escalation_level = 'suspended',
           suspended_at = now(),
           updated_at = now()
     where id = v_rec.id;

    -- 2) غلق السيستم على الموظف وإيقافه عن العمل
    update public.employees
       set status = 'suspended',
           is_active = false,
           updated_at = now()
     where id = v_rec.employee_id;

    update public.profiles
       set status = 'suspended',
           updated_at = now()
     where employee_id = v_rec.employee_id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.suspended', 'security', 'critical',
      'instant_attendance_penalties', v_rec.id,
      'غلق السيستم وتعليق موظف عن العمل: ' || coalesce(v_emp_name, 'موظف') || ' — لعدم سداد غرامة 500 ج.م في اليوم الثاني',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'amount', v_rec.current_amount)
    );

    -- 3) إشعار الموظف والمديرين
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

    -- 4) إرسال إشعار فوري لكامل الفريق (كل الموظفين النشطين بالشركة)
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

    v_escalated := v_escalated + 1;
  end loop;

  return v_escalated;
exception
  when others then
    perform public.log_audit_event(
      'instant_penalty.escalation_failed', 'operations', 'error',
      'instant_attendance_penalties', null,
      'فشل التصعيد التلقائي للغرامات الفورية', null,
      jsonb_build_object('error', sqlerrm)
    );
    return 0;
end;
$function$;

comment on function public.auto_escalate_instant_penalties() is
  '0550: تصعيد الغرامات — المضاعفة تلقائية؛ التعليق فقط لمن يملك تغيير الحالة، وإلا يُسجَّل instant_penalty.suspension_pending ويبقى الصف doubled.';

commit;
