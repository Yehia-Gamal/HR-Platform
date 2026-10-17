-- ===========================================================================
-- 0691: إثراء صندوق الإجراءات الموحد ببيانات وصور أصحاب الطلبات والتقييمات
-- ===========================================================================
-- المشكلة:
-- كان get_universal_action_center يُعيد فقط title و subtitle دون تضمين:
-- photo_url للموظف، request_type، request_number، employee_name، مما
-- يحرم شاشات الموبايل (والمدير التنفيذي) من صور الموظفين وأسمائهم الصريحة
-- ويضطر الواجهة لمحاولة الربط مع RPC آخر قد لا يتطابق أو يتأخر.
--
-- الحل:
-- إدراج:
-- 1) employeeName: الاسم العربي الكامل لصاحب الطلب أو التقييم.
-- 2) photoUrl: الرابط المباشر لصورة الموظف في Supabase Storage.
-- 3) requestType: نوع الطلب (mission, leave, late_permit...).
-- 4) requestNumber: رقم الطلب التسلسلي (#574, #572...).
-- 5) requestTitle و requestReason: العنوان التفصيلي والسبب.
-- 6) منح الصلاحية لجميع المراجعين والمدير التنفيذي لمطالعة الصندوق بلا عوائق.
-- ===========================================================================

begin;

create or replace function public.get_universal_action_center(p_limit integer default 100)
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 with actions as (
  select 'request-'||r.id::text id,
         'request'::text kind,
         coalesce(r.title,'طلب رقم '||r.request_number::text) title,
         e.full_name_ar subtitle,
         case when r.decision_due_at<now()+interval '4 hours' then 'urgent' else 'high' end priority,
         r.workflow_status status,
         r.decision_due_at due_at,
         '/hr/requests?request='||r.id::text action_url,
         coalesce(r.updated_at,r.created_at) source_updated_at,
         e.full_name_ar as employee_name,
         e.photo_url as photo_url,
         r.request_type as request_type,
         r.request_number as request_number,
         r.title as request_title,
         r.reason as request_reason
  from public.requests r join public.employees e on e.id=r.employee_id
  left join lateral (
    select rs.step_order, rs.escalation_deadline
      from public.request_steps rs
     where rs.request_id = r.id
       and rs.status in ('active','escalated','pending')
     order by (rs.status = 'active') desc, rs.step_order
     limit 1
  ) cs on true
  where r.status='pending'
    and (
      r.employee_id=public.current_employee_id()
      or r.manager_employee_id=public.current_employee_id()
      or (public.current_has_active_role(array['operations-manager-1'])
          and (
            coalesce(cs.step_order,0) >= 2
            or coalesce(cs.escalation_deadline, r.escalation_deadline) < now()
            or r.workflow_status in ('escalated','awaiting_operator')
          ))
      or public.can_access_employee(r.employee_id,'requests.request.approve')
      or public.current_is_executive_secretary()
      or public.current_has_active_role(array['executive', 'executive-director', 'general-manager', 'admin', 'super-admin'])
    )
  union all
  select 'kpi-'||k.id::text,
         'kpi',
         'تقييم '||e.full_name_ar||' يحتاج إجراء',
         e.employee_code,
         case when k.current_stage='manager_final' then 'urgent' else 'high' end,
         k.current_stage,
         null::timestamptz,
         '/hr/performance',
         coalesce(k.updated_at,k.created_at),
         e.full_name_ar as employee_name,
         e.photo_url as photo_url,
         'kpi'::text as request_type,
         null::integer as request_number,
         null::text as request_title,
         null::text as request_reason
  from public.kpi_evaluations k join public.employees e on e.id=k.employee_id
  where (k.current_stage='self' and k.employee_id=public.current_employee_id())
     or (k.current_stage in ('manager_review','manager_final') and public.kpi_is_direct_manager(k.employee_id))
     or (k.current_stage='hr_review' and public.current_is_hr_reviewer())
  union all
  select 'decision-'||d.id::text,
         'decision',
         d.title,
         'متابعة قرار رسمي',
         'normal',
         d.status,
         null::timestamptz,
         '/admin/official-feed',
         coalesce(d.updated_at,d.created_at),
         null::text as employee_name,
         null::text as photo_url,
         'decision'::text as request_type,
         null::integer as request_number,
         d.title as request_title,
         null::text as request_reason
  from public.administrative_decisions d where d.status='published' and d.requires_read_receipt=true
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',id,
   'kind',kind,
   'title',title,
   'subtitle',subtitle,
   'priority',priority,
   'status',status,
   'dueAt',due_at,
   'actionUrl',action_url,
   'sourceUpdatedAt',source_updated_at,
   'employeeName',employee_name,
   'photoUrl',photo_url,
   'requestType',request_type,
   'requestNumber',request_number,
   'requestTitle',request_title,
   'requestReason',request_reason
 ) order by source_updated_at desc nulls last),'[]'::jsonb)
 from (select * from actions order by source_updated_at desc limit greatest(1,least(coalesce(p_limit,100),500))) limited;
$$;

revoke all on function public.get_universal_action_center(integer) from public,anon;
grant execute on function public.get_universal_action_center(integer) to authenticated;
comment on function public.get_universal_action_center(integer) is
  '0690: صندوق الإجراءات الموحد مع إثراء بطاقات الطلبات بصور الموظفين، الاسم العربي، ونوع ورقم الطلب.';

commit;
