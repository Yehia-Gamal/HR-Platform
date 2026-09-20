-- ═══════════════════════════════════════════════════════════════
-- 0529: إصلاح خطأ 42803 في get_association_projects (ORDER BY خارج jsonb_agg)
--
-- الجذر الحقيقي الذي طاردته 0521 → 0528 تحت عنوان «ذاكرة مخطط PostgREST»:
--
--     select jsonb_agg(jsonb_build_object(...))
--     from public.association_projects p
--     ...
--     order by <أعمدة p>          ← هنا العطل
--
-- في استعلام تجميعي بلا GROUP BY، لا يجوز أن يشير ORDER BY إلى عمود غير مُجمَّع
-- ولا مُجمَّع عليه → PostgreSQL يرفع 42803:
--   "column p.updated_at must appear in the GROUP BY clause or be used in an
--    aggregate function".
-- الدالة تُنشأ بنجاح لأن plpgsql لا يُحلّل SQL المضمَّن دلالياً وقت الإنشاء،
-- فيظهر العطل وقت التشغيل فقط — وهو ما بدا كأنه «الدالة غير مرئية لـ PostgREST».
--
-- وحتى لو نفّذ، فترتيب صف ناتج واحد لا يرتّب عناصر المصفوفة إطلاقاً؛ الترتيب
-- المقصود لم يكن يعمل أصلاً. الصواب هو ORDER BY داخل jsonb_agg نفسها.
--
-- ملاحظة: PostgREST لا يستبعد الدوال VOLATILE من مخطط الـ API؛ يستدعيها عبر
-- POST (وهو ما يفعله supabase-js .rpc). STABLE صحيحة هنا على أي حال ونُبقيها.
-- لتحديث ذاكرة المخطط فعلياً: NOTIFY pgrst, 'reload schema'.
--
-- نحافظ على كل ما أصابته 0528: STABLE + SET search_path + المنح.
-- ═══════════════════════════════════════════════════════════════

create or replace function public.get_association_projects()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
  v_emp    uuid;
  v_full   boolean;
begin
  v_emp  := public.current_employee_id();
  v_full := public.current_is_full_access();

  if not v_full and v_emp is null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'projects', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',              p.id,
          'code',            p.code,
          'name',            p.name,
          'description',     p.description,
          'departmentId',    p.department_id,
          'departmentName',  d.name,
          'ownerId',         p.owner_employee_id,
          'ownerName',       e.full_name_ar,
          'status',          p.status,
          'approvalStatus',  p.approval_status,
          'priority',        p.priority,
          'progress',        p.progress,
          'startDate',       p.start_date,
          'targetEndDate',   p.target_end_date,
          'lastUpdateAt',    p.last_update_at,
          'lastUpdateNote',  p.last_update_note,
          'approvedBy',      p.approved_by,
          'approvedAt',      p.approved_at,
          'rejectionReason', p.rejection_reason,
          'totalSteps',      (select count(*) from public.association_project_steps s where s.project_id = p.id),
          'completedSteps',  (select count(*) from public.association_project_steps s where s.project_id = p.id and s.status = 'done'),
          'remainingSteps',  (select count(*) from public.association_project_steps s where s.project_id = p.id and s.status not in ('done','cancelled')),
          'blockedSteps',    (select count(*) from public.association_project_steps s where s.project_id = p.id and s.status = 'blocked'),
          'ledStatus',       case
                                when p.approval_status = 'pending_approval' then 'pending'
                                when p.approval_status = 'rejected'         then 'rejected'
                                when p.approval_status = 'draft'            then 'draft'
                                when p.status in ('completed','cancelled')  then 'stale'
                                when p.status = 'on_hold'                   then 'halted'
                                when p.last_update_at is null               then 'stale'
                                when p.last_update_at < now() - interval '30 days' then 'stale'
                                when p.last_update_at < now() - interval '14 days' then 'halted'
                                else 'active'
                              end
        )
        -- ← الترتيب داخل التجميعة: هذا ما يرتّب عناصر المصفوفة فعلاً،
        --    وهو ما يمنع 42803. لا تنقله خارج jsonb_agg مرة أخرى.
        order by
          case p.approval_status when 'pending_approval' then 0 when 'draft' then 1 else 2 end,
          case p.priority when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
          p.updated_at desc
      )
      from public.association_projects p
      join public.departments d on d.id = p.department_id
      join public.employees   e on e.id = p.owner_employee_id
      where v_full or p.owner_employee_id = v_emp
    ), '[]'::jsonb),
    'lastUpdatedAt', now(),
    'isFullAccess',  v_full
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_association_projects() from public, anon;
grant execute on function public.get_association_projects() to authenticated, service_role;

comment on function public.get_association_projects() is
  '0529: قائمة مشاريع الجمعية — STABLE + search_path مثبّت + ORDER BY داخل jsonb_agg (إصلاح 42803).';
