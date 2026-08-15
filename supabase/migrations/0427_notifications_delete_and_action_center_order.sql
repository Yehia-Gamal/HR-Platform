-- Migration 0427: delete_my_notifications + Action Center newest-first ordering
--
-- 1) حذف إشعارات المالك: لا يجوز حذف إشعارات الآخرين حتى للمسؤول الكامل —
--    الإشعارات owner-scoped (مطابقة لـ mark_my_notifications_read في 0016).
-- 2) مركز الإجراءات الموحد: ترتيب الأحدث أولاً دائماً بدلاً من المهلة — طلب
--    المستخدم: ظهور أحدث الأنشطة في أعلى القائمة (الترتيب بالأولوية والمهلة
--    كان يُقدّم القديم على الجديد فتبدو القائمة معكوسة).

create or replace function public.delete_my_notifications(p_ids uuid[] default null)
returns integer
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare v_count integer;
begin
  delete from public.notifications
  where recipient_user_id = auth.uid()
    and (p_ids is null or id = any(p_ids));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.delete_my_notifications(uuid[]) from public, anon;
grant execute on function public.delete_my_notifications(uuid[]) to authenticated;
comment on function public.delete_my_notifications(uuid[]) is
  'يحذف إشعارات المستخدم الحالي فقط — p_ids = null يحذف الكل، وإلا المحددة فقط.';

-- مركز الإجراءات: الأحدث أولاً — تُسحب العناصر الأحدث ثم تُرتَّب الأحدث أولاً
-- بغض النظر عن الأولوية أو المهلة (المستخدم طلب الترتيب الزمني التنازلي).
create or replace function public.get_universal_action_center(p_limit integer default 100)
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 with actions as (
  select 'request-'||r.id::text id,'request'::text kind,coalesce(r.title,'طلب رقم '||r.request_number::text) title,e.full_name_ar subtitle,
   case when r.decision_due_at<now()+interval '4 hours' then 'urgent' else 'high' end priority,r.workflow_status status,r.decision_due_at due_at,'/hr/requests'::text action_url,coalesce(r.updated_at,r.created_at) source_updated_at
  from public.requests r join public.employees e on e.id=r.employee_id
  where r.status='pending' and (r.employee_id=public.current_employee_id() or public.can_access_employee(r.employee_id,'requests.request.approve') or public.current_is_executive_secretary())
  union all
  select 'kpi-'||k.id::text,'kpi','تقييم '||e.full_name_ar||' يحتاج إجراء',e.employee_code,
   case when k.current_stage='manager_final' then 'urgent' else 'high' end,k.current_stage,null::timestamptz,'/hr/performance',coalesce(k.updated_at,k.created_at)
  from public.kpi_evaluations k join public.employees e on e.id=k.employee_id
  where (k.current_stage='self' and k.employee_id=public.current_employee_id())
     or (k.current_stage in ('manager_review','manager_final') and public.kpi_is_direct_manager(k.employee_id))
     or (k.current_stage='hr_review' and public.current_is_hr_reviewer())
     or (k.current_stage not in ('finalized','closed','archived') and public.current_is_executive_secretary())
  union all
  select 'decision-'||d.id::text,'decision',d.title,'متابعة قرار رسمي','normal',d.status,null::timestamptz,'/admin/official-feed',coalesce(d.updated_at,d.created_at)
  from public.administrative_decisions d where d.status='published' and d.requires_read_receipt=true
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'subtitle',subtitle,'priority',priority,'status',status,'dueAt',due_at,'actionUrl',action_url,'sourceUpdatedAt',source_updated_at) order by source_updated_at desc nulls last),'[]'::jsonb)
 from (select * from actions order by source_updated_at desc limit greatest(1,least(coalesce(p_limit,100),500))) limited;
$$;
revoke all on function public.get_universal_action_center(integer) from public,anon;
grant execute on function public.get_universal_action_center(integer) to authenticated;