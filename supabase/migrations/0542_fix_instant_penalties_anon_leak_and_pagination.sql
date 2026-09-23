-- ═══════════════════════════════════════════════════════════════
-- 0542: إغلاق تسريب get_instant_penalties لغير المصادَقين + إصلاح الترقيم
--
-- (1) P0 — حارس مقلوب + منح لـ anon:
--
--       if auth.uid() is not null and not ( ...فحوص الصلاحية... ) then
--         raise exception 'غير مسموح';
--       end if;
--
--     عند الاستدعاء بلا جلسة يكون auth.uid() = null، فيصبح الشرط
--     `null is not null` = false، ويقصُر التقييم قبل فحوص الصلاحية →
--     **لا يُرفع أي استثناء** وتُرجع الدالة كل الصفوف. ومع
--       grant execute ... to authenticated, anon;   (0536 ثم 0541)
--     يعني ذلك أن أي حامل للمفتاح العام المنشور داخل حزمة الويب وAPK
--     يقرأ سجلات الغرامات كاملة (اسم الموظف، كوده، القسم، المبالغ، التواريخ)
--     بلا تسجيل دخول. 0540 سحبت anon من دالتين أخريين لكنها لم تمسّ هذه،
--     ثم أعاد 0541 منحها لـ anon.
--
--     تنبيه: `current_user` داخل SECURITY DEFINER = مالك الدالة لا المستدعي،
--     فالنمط الشائع `current_user not in ('postgres','service_role')` لا يُطلق
--     أبداً ولا يصلح حارساً (وثّق ذلك مؤلف 0483). ولأن هذه الدالة لا يستدعيها
--     أي عامل خادمي — الويب فقط — فالحارس الصحيح هو رفض غياب الجلسة مباشرة.
--     ملاحظة: 0511 كانت تسحب anon أصلاً؛ 0536 ثم 0541 أعادتا منحه — انحدار.
--
-- (2) P1 — limit/offset بلا أثر:
--     `select jsonb_agg(...) from ... limit N offset M` يقيّد صفوف *النتيجة*
--     (وهي صف واحد لأن الاستعلام تجميعي) لا الصفوف المُجمَّعة. فكانت الدالة
--     تُرجع كل الصفوف المطابقة دائماً مهما كان p_limit — ترقيم معطّل.
--     الصواب: limit/offset داخل استعلام فرعي ثم التجميع.
--     ملاحظة مقصودة: الافتراضي صار null (= بلا تقييد) بدل 200، لأن الويب
--     لا يمرّر p_limit؛ لو فُعِّل الحد 200 فجأة لاختفت صفوف من شاشة الغرامات
--     بصمت. الآن: من لا يمرّر شيئاً يرى ما يراه اليوم، ومن يمرّر قيمة تُطبَّق.
--
-- (3) سحب anon من دالتي الإعفاء (0532/0533) — تكشفان حالة إعفاء أي موظف
--     لأي مجهول يملك معرّف الموظف.
--
-- ملاحظة متابعة: 11 دالة أخرى تحمل نفس الحارس المقلوب لكنها ممنوحة لـ
-- authenticated فقط، فلا تصلها طلبات anon عبر PostgREST (دور anon بلا EXECUTE).
-- وهي فخّ كامن لا ثغرة حيّة — تُصلَح باستبدال كنوني منفصل.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ═══════════════════════════════════════════════
-- 1. سحب anon فوراً (يغلق الثغرة حتى قبل استبدال الجسم)
-- ═══════════════════════════════════════════════

revoke execute on function public.get_instant_penalties(uuid, text, date, date, integer, integer) from anon;
revoke execute on function public.is_employee_attendance_exempt(uuid) from anon;
revoke execute on function public.is_employee_penalty_exempt(uuid) from anon;

-- ═══════════════════════════════════════════════
-- 2. get_instant_penalties — استبدال كنوني
--    حارس صحيح + ترقيم فعّال. نفس مفاتيح JSON بلا تغيير في العقد.
-- ═══════════════════════════════════════════════

create or replace function public.get_instant_penalties(
  p_employee_id uuid default null::uuid,
  p_status text default null::text,
  p_date_from date default null::date,
  p_date_to date default null::date,
  p_limit integer default null::integer,   -- null = بلا تقييد (سلوك اليوم)
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  -- تتطلب جلسة مستخدم. لا استثناء لـ«غياب الجلسة»:
  --   • لا يستدعيها أي عامل خادمي — الويب فقط (useInstantPenalties.ts).
  --   • و current_user داخل SECURITY DEFINER يساوي *مالك الدالة* لا المستدعي،
  --     فلا يصلح للتمييز بين anon و service_role (وثّق ذلك مؤلف 0483 نفسه).
  --     أي فحص على current_user هنا لا يُطلق أبداً — لذا نرفض غياب الجلسة مباشرة.
  if auth.uid() is null then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'payroll.run.manage', 'payroll.run.approve', 'people.employee.read', 'attendance.record.read'
    ])
    or (p_employee_id is not null and p_employee_id = public.current_employee_id())
    or (p_employee_id is not null and exists (
      select 1 from public.profiles where id = auth.uid() and employee_id = p_employee_id
    ))
  ) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id',                     t.id,
        'employeeId',             t.employee_id,
        'employeeName',           t.employee_name,
        'employeeCode',           t.employee_code,
        'departmentName',         t.department_name,
        'workDate',               t.work_date,
        'lateMinutes',            t.late_minutes,
        'originalAmount',         t.original_amount,
        'currentAmount',          t.current_amount,
        'currency',               t.currency,
        'status',                 t.status,
        'escalationLevel',        t.escalation_level,
        'paidAt',                 t.paid_at,
        'confirmedBy',            t.confirmed_by,
        'suspendedAt',            t.suspended_at,
        'suspensionLiftedAt',     t.suspension_lifted_at,
        'notes',                  t.notes,
        'createdAt',              t.created_at,
        'excuseStatus',           t.excuse_status,
        'excuseText',             t.excuse_text,
        'excuseAttachmentUrl',    t.excuse_attachment_url,
        'excuseSubmittedAt',      t.excuse_submitted_at,
        'excuseReviewedAt',       t.excuse_reviewed_at,
        'excuseNotes',            t.excuse_notes,
        'paymentMethod',          t.payment_method,
        'receiptAttachmentUrl',   t.receipt_attachment_url,
        'receiptSubmittedAt',     t.receipt_submitted_at,
        'receiptReferenceNumber', t.receipt_reference_number
      )
      order by t.work_date desc, t.created_at desc
    )
    -- الترقيم داخل استعلام فرعي: limit/offset على استعلام تجميعي بلا أثر.
    from (
      select
        p.id,
        p.employee_id,
        e.full_name_ar                        as employee_name,
        e.employee_code,
        d.name                                as department_name,
        p.work_date,
        p.late_minutes,
        p.original_amount,
        p.current_amount,
        p.currency,
        p.status,
        p.escalation_level,
        p.paid_at,
        p.confirmed_by,
        p.suspended_at,
        p.suspension_lifted_at,
        p.notes,
        p.created_at,
        coalesce(p.excuse_status, 'none')     as excuse_status,
        p.excuse_text,
        p.excuse_attachment_url,
        p.excuse_submitted_at,
        p.excuse_reviewed_at,
        p.excuse_notes,
        coalesce(p.payment_method, 'cash')    as payment_method,
        p.receipt_attachment_url,
        p.receipt_submitted_at,
        p.receipt_reference_number
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
      left join public.departments d on d.id = e.department_id
      where (p_employee_id is null or p.employee_id = p_employee_id)
        and (p_status is null or p.status = p_status)
        and (p_date_from is null or p.work_date >= p_date_from)
        and (p_date_to is null or p.work_date <= p_date_to)
      order by p.work_date desc, p.created_at desc
      -- LIMIT NULL في PostgreSQL = بلا تقييد. الاستدعاءات القائمة (الويب لا
      -- يمرّر p_limit) تبقى كما هي تماماً، ومن يمرّر قيمة يحصل على تقييد فعلي.
      limit case when p_limit is null then null else greatest(1, p_limit) end
      offset greatest(0, coalesce(p_offset, 0))
    ) t
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_instant_penalties(uuid, text, date, date, integer, integer) from public, anon;
grant execute on function public.get_instant_penalties(uuid, text, date, date, integer, integer) to authenticated, service_role;

comment on function public.get_instant_penalties(uuid, text, date, date, integer, integer) is
  '0542: قائمة الغرامات الفورية — حارس صحيح (لا تمرير للمجهولين) + ترقيم فعّال داخل استعلام فرعي.';

commit;
