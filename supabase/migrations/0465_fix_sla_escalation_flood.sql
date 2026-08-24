-- =====================================================================
-- 0465: إصلاح طوفان إشعارات التصعيد (SLA Escalation Flood)
-- ---------------------------------------------------------------------
-- الجذر: عند تجاوز مهلة الخطوة 1 كانت الدالة تصعّد وتُفعّل الخطوة 2 لكنها
-- تركت escalation_deadline للخطوة 1 في الماضي، فكان cron (كل 5 دقائق)
-- يعيد اختيارها ويعيد التصعيد والإشعار بلا توقف (201 إشعاراً لطلب واحد!).
--
-- الإصلاح:
--   1) بعد تصعيد الخطوة 1 تُضبط مهلتها إلى +24 ساعة — فتصبح التذكيرات
--      دورية يومية كما صُمّمت، لا كل 5 دقائق.
--   2) معالجة بيانات قائمة: كل خطوة escalated/active انتهت مهلتها تُضبط
--       مهلتها إلى +24 ساعة حتى لا تنفجر بالتكرار عند أول تشغيل بعد النشر.
--   3) تنظيف الإشعارات: لكل (مستلم، طلب) خلال آخر 7 أيام يُحتفظ بأقدم
--      إشعار تصعيد high ويُحذف الباقي المكرر.
-- =====================================================================

begin;

-- ─── 1) إصلاح دالة process_request_sla ──────────────────────────────────────
create or replace function public.process_request_sla(p_limit integer default 200)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count    integer := 0;
  v_row      record;
  v_next     record;
  v_ops_emp  uuid;
  v_target   uuid;
  v_role     text;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;

  v_ops_emp := public.first_active_employee_for_role('operations-manager-1');

  for v_row in
    select
      rs.id          as step_id,
      rs.request_id,
      rs.step_order,
      rs.status      as step_status,
      r.employee_id,
      r.manager_employee_id,
      r.title,
      r.request_type
    from public.request_steps rs
    join public.requests r on r.id = rs.request_id
    where r.status = 'pending'
      and rs.status in ('active', 'escalated')
      and rs.escalation_deadline is not null
      and rs.escalation_deadline < now()
    order by rs.escalation_deadline
    limit greatest(1, least(coalesce(p_limit, 200), 2000))
    for update of rs skip locked
  loop
    -- ── الخطوة النهائية (أبو عمار أو أي مرحلة >= 2): لا ترقية أبعد ──
    --    فقط تذكير دوري لأبو عمار وإعادة ضبط المهلة (24 ساعة).
    if v_row.step_order >= 2 then
      if v_ops_emp is not null then
        update public.request_steps
          set assignee_employee_id = coalesce(assignee_employee_id, v_ops_emp),
              assignee_role_slug   = 'operations-manager-1',
              updated_at = now()
        where id = v_row.step_id;

        perform public.notify_employee(
          v_ops_emp,
          'تذكير: طلب لم يُبتَّ فيه بعد',
          coalesce(v_row.title, '') || ' — يحتاج قرارك الآن (المدير).
المدير المباشر لم يبتّ والطلب محوَّل لك كقرار نهائي.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'final_reminder',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;
      -- صفِّر deadline لمنع تكرار التذكير الفوري (24 ساعة من الآن)
      update public.request_steps
        set escalation_deadline = now() + interval '24 hours', updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    -- ── الخطوة 1 (المدير المباشر): تصعيد إلى الخطوة 2 (أبو عمار) ──
    select * into v_next
    from public.request_steps
    where request_id = v_row.request_id
      and step_order = v_row.step_order + 1
    limit 1;

    -- وسمّ الخطوة الحالية كـ escalated + خنّق مهلتها 24 ساعة.
    -- (0465: كان يُترك deadline في الماضي فيعيد الـcron اختيارها كل 5 دقائق!)
    update public.request_steps
      set status = 'escalated',
          escalated_at = coalesce(escalated_at, now()),
          escalation_deadline = now() + interval '24 hours',
          updated_at = now()
    where id = v_row.step_id;

    if v_next.id is not null then
      v_target := v_ops_emp;
      v_role   := 'operations-manager-1';

      -- فعّل الخطوة التالية (أبو عمار) — مهلة ساعتين
      update public.request_steps
        set status = 'active',
            assignee_employee_id = coalesce(v_target, assignee_employee_id),
            assignee_role_slug = coalesce(v_role, assignee_role_slug),
            due_at = now() + interval '2 hours',
            escalation_deadline = now() + interval '2 hours',
            updated_at = now()
      where id = v_next.id;

      update public.workflow_instances
        set current_step_order = v_next.step_order, updated_at = now()
      where request_id = v_row.request_id and status = 'running';

      update public.requests
        set workflow_status = 'awaiting_operator',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.request_id;

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata
      ) values (
        v_row.request_id, null, 'escalate', 'pending', 'pending',
        'تصعيد تلقائي — تجاوز مهلة المدير المباشر (ساعتان)',
        jsonb_build_object('tier', v_next.step_order, 'targetRole', v_role)
      );

      -- إشعار أبو عمار (الخطوة 2)
      if v_target is not null then
        perform public.notify_employee(
          v_target,
          'طلب محوَّل إليك — مدير التشغيل 1',
          coalesce(v_row.title, '') || ' — يمكنك البت فيه الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', v_role,
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      -- إشعار المدير التنفيذي (كامل الشاشة) عند التصعيد الأول فقط
      if v_next.status is distinct from 'active' then
        perform public.notify_executive_fullscreen(
          'تصعيد طلب — للمتابعة',
          coalesce(v_row.title, ''),
          'request',
          'request', v_row.request_id,
          '/requests/' || v_row.request_id,
          jsonb_build_object(
            'escalation', 'executive_notify',
            'tier', v_next.step_order
          )
        );
      end if;
    else
      -- لا توجد خطوة تالية (طلب قديم بلا بنية): تصعيد عام
      update public.requests
        set workflow_status = 'escalated',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.request_id;
    end if;

    v_count := v_count + 1;
  end loop;

  -- سجل صحة الـ cron
  insert into public.cron_health_log(job_name, rows_affected, status)
  values ('process_request_sla', v_count, 'ok');

  return v_count;

exception when others then
  insert into public.cron_health_log(job_name, rows_affected, status, detail)
  values ('process_request_sla', 0, 'error', sqlerrm);
  raise;
end $$;

revoke execute on function public.process_request_sla(integer) from public, anon;
grant execute on function public.process_request_sla(integer) to service_role;

-- ─── 2) معالجة الخطوات العالقة حالياً (مهلة ماضية) → +24 ساعة ───────────────
update public.request_steps rs
   set escalation_deadline = now() + interval '24 hours',
       updated_at = now()
  from public.requests r
 where r.id = rs.request_id
   and r.status = 'pending'
   and rs.status in ('active','escalated')
   and rs.escalation_deadline is not null
   and rs.escalation_deadline < now();

-- ─── 3) تنظيف الإشعارات المكررة: احتفظ بأقدم إشعار لكل (مستلم، طلب) ─────────
delete from public.notifications n
using public.notifications keeper
where n.category = 'request'
  and n.priority = 'high'
  and n.created_at > now() - interval '7 days'
  and n.entity_id is not null
  and keeper.recipient_employee_id = n.recipient_employee_id
  and keeper.entity_id = n.entity_id
  and keeper.category = 'request'
  and keeper.priority = 'high'
  and (keeper.created_at, keeper.id) < (n.created_at, n.id);

commit;

notify pgrst, 'reload schema';
