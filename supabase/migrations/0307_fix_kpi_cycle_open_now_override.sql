-- =====================================================================
-- 0302_fix_kpi_cycle_open_now_override.sql
-- =====================================================================
-- المشكلة: بعد ضغط «تجهيز الدورة» تُنشأ الدورة بحالة 'draft' ولا تُفتح
-- للموظفين على الموبايل لتقييم أنفسهم. السببان:
--
--   1) الواجهة ترسل p_open_now=false دائماً (KpiCyclesPage.tsx line 96).
--   2) حتى مع p_open_now=true، ترفض الدالة الفتح ما لم يكن now() بين
--      يوم 19 و25 من الشهر — نافذة مجدولة لا معنى لها عندما يطلب
--      المشرف الفتح الفوري يدوياً.
--
-- الحل: عندما يطلب المشرف p_open_now=true صراحة، نفتح الدورة فوراً
-- بلا قيد على التاريخ. النافذة المجدولة تبقى فقط للجدولة التلقائية
-- (cron)، لا للفتح اليدوي الصريح.
--
-- Idempotent: CREATE OR REPLACE فقط.
-- =====================================================================

begin;

create or replace function public.create_kpi_cycle_admin(
 p_month date,p_template_id uuid,p_self_due timestamptz,p_manager_due timestamptz,
 p_secretary_due timestamptz,p_executive_due timestamptz,p_open_now boolean default true,
 p_use_parallel_flow boolean default false
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_id uuid; v_month date:=date_trunc('month',p_month)::date; v_template uuid; v_policy uuid;
 v_open timestamptz; v_deadline timestamptz; v_status text:='draft';
begin
 if not (public.current_is_full_access() or public.current_is_executive_secretary()) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select id into strict v_template from public.kpi_templates where official_code='OFFICIAL_KPI_100' and is_active;
 if p_template_id is distinct from v_template then raise exception 'ONLY_OFFICIAL_KPI_TEMPLATE_IS_ALLOWED'; end if;
 select id into strict v_policy from public.kpi_policy_versions where is_active;
 v_open:=((v_month+19)::timestamp at time zone 'Africa/Cairo');
 v_deadline:=(((v_month+25)::timestamp at time zone 'Africa/Cairo')-interval '1 second');
 -- ★ الفتح الفوري: عندما يطلب المشرف p_open_now=true صراحة، نفتح فوراً
 --   بغض النظر عن التاريخ. النافذة المجدولة تبقى للجدولة التلقائية فقط.
 if coalesce(p_open_now,false) then v_status:='open'; end if;
 insert into public.kpi_cycles(period_month,status,template_id,scheduled_open_at,deadline_at,self_due_at,manager_due_at,secretary_due_at,executive_due_at,opened_at,opened_by,policy_version_id,use_parallel_flow,created_by)
 values(v_month,v_status,v_template,v_open,v_deadline,v_deadline,v_deadline,v_deadline,v_deadline,case when v_status='open' then now() end,case when v_status='open' then public.current_employee_id() end,v_policy,coalesce(p_use_parallel_flow,false),auth.uid())
 on conflict(period_month) do update set
  template_id=excluded.template_id,scheduled_open_at=excluded.scheduled_open_at,deadline_at=excluded.deadline_at,
  self_due_at=excluded.self_due_at,manager_due_at=excluded.manager_due_at,
  secretary_due_at=excluded.secretary_due_at,executive_due_at=excluded.executive_due_at,
  policy_version_id=coalesce(kpi_cycles.policy_version_id,excluded.policy_version_id),
  use_parallel_flow=excluded.use_parallel_flow,updated_at=now()
 returning id into v_id;
 insert into public.kpi_evaluations(employee_id,cycle_id,template_id,stage,current_stage,workflow_status,locked,created_by)
 select e.id,v_id,v_template,'self','self',case when v_status='open' then 'OPEN_FOR_SELF_EVALUATION' else 'DRAFT' end,v_status<>'open',auth.uid()
 from public.employees e
 where e.is_active and not coalesce(e.is_deleted,false) and e.status='active'
   and not exists(
     select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
     where ur.user_id=e.user_id and r.slug in ('executive','executive-director')
       and (ur.effective_from is null or ur.effective_from<=now())
       and (ur.effective_to is null or ur.effective_to>now())
   )
 on conflict(employee_id,cycle_id,template_id) do nothing;
 perform public.refresh_kpi_attendance_inputs(v_id);
 perform public.log_audit_event('kpi.cycle.created','workflow','notice','kpi_cycles',v_id,'إنشاء دورة KPI',null,jsonb_build_object('month',v_month,'openAt',v_open,'deadline',v_deadline,'status',v_status,'parallelFlow',p_use_parallel_flow));
 return v_id;
end $$;

revoke execute on function public.create_kpi_cycle_admin(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean, boolean) from public, anon;
grant  execute on function public.create_kpi_cycle_admin(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean, boolean) to authenticated;

notify pgrst, 'reload schema';

commit;
