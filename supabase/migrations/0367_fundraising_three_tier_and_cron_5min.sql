-- ═══════════════════════════════════════════════════════════════════════════════
-- 0365: تمديد المسار الثلاثي على «الفاندي/الإذن» + تسريع cron إلى كل 5 دقائق
-- ═══════════════════════════════════════════════════════════════════════════════
-- (1) 0364 غطى leave/mission/convoy/generic فقط. نمدّد نفس المسار الثلاثي
--     (مدير 2h → أوبريشن 4h → HR 48h) على fundraising + attendance_permit.
-- (2) cron job hr_request_sla ما زال */10؛ نُسرّعه إلى */5 لالتقاط مهلة
--     الساعتين بدقة. نستخدم jobid (alter_job بـ jobname لم يلقِ التأثير).
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_type text;
  v_def uuid;
begin
  foreach v_type in array array['fundraising','attendance_permit'] loop
    select id into v_def
    from public.workflow_definitions
    where request_type = v_type and is_default = true and is_active = true
    order by version desc limit 1;

    if v_def is null then
      insert into public.workflow_definitions (
        code, name_ar, description, request_type, version, is_active, is_default,
        auto_escalate, default_due_hours, config
      ) values (
        'three-tier-' || v_type,
        case v_type
          when 'fundraising' then 'اعتماد الفاندي — مدير ثم أوبريشن ثم HR'
          else 'اعتماد الإذن — مدير ثم أوبريشن ثم HR'
        end,
        'سير ثلاثي: مدير مباشر (مهلة ساعتان) → أوبريشن (مهلة 4 ساعات) → HR. الإجراء متاح متزامنًا لكل الأدوار طوال الوقت.',
        v_type, 1, true, true, true, 48,
        jsonb_build_object(
          'tierHours', jsonb_build_object('manager', 2, 'operations', 4, 'hr', 48),
          'concurrentActors', jsonb_build_array('direct_manager','operations','executive','hr')
        )
      )
      returning id into v_def;
    else
      update public.workflow_definitions
        set name_ar = case v_type
                       when 'fundraising' then 'اعتماد الفاندي — مدير ثم أوبريشن ثم HR'
                       else 'اعتماد الإذن — مدير ثم أوبريشن ثم HR'
                      end,
            description = 'سير ثلاثي: مدير مباشر (مهلة ساعتان) → أوبريشن (مهلة 4 ساعات) → HR. الإجراء متاح متزامنًا لكل الأدوار طوال الوقت.',
            config = jsonb_build_object(
              'tierHours', jsonb_build_object('manager', 2, 'operations', 4, 'hr', 48),
              'concurrentActors', jsonb_build_array('direct_manager','operations','executive','hr')
            ),
            updated_at = now()
      where id = v_def;
    end if;

    delete from public.workflow_steps where definition_id = v_def;

    insert into public.workflow_steps
      (definition_id, step_order, name_ar, step_type, approver_type, approver_role_slug, sla_hours, escalate_after_hours, approver_permission, is_optional, allow_delegate, is_active)
    values
      (v_def, 1, 'المدير المباشر', 'approval', 'direct_manager', null, 2, 2, 'requests.approve', false, true, true),
      (v_def, 2, 'الأوبريشن', 'approval', 'operator', 'operations-officer', 4, 4, 'requests.approve', true, true, true),
      (v_def, 3, 'الموارد البشرية', 'approval', 'role', 'hr-manager', 48, null, 'requests.approve', true, true, true);
  end loop;
end $$;

-- (2) تسريع cron إلى كل 5 دقائق عبر jobid.
do $$
declare v_jid bigint;
begin
  select jobid into v_jid from cron.job where jobname = 'hr_request_sla';
  if v_jid is not null then
    perform cron.alter_job(job_id => v_jid, schedule => '*/5 * * * *');
  end if;
exception when others then
  raise notice 'cron alter skipped: %', sqlerrm;
end $$;

notify pgrst, 'reload schema';
