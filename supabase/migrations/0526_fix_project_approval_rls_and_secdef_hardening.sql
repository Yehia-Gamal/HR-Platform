-- ═══════════════════════════════════════════════════════════════
-- 0526: إغلاق ثغرة الاعتماد الذاتي للمشاريع + تحصين دوال SECURITY DEFINER
--
-- (1) P0 — سياسات 0518 كانت تُبطل دورة الموافقات التي أنشأتها:
--     • projects_insert_auth ... with check (true)  → أي موظف يُدرج صفاً
--       بـ approval_status = 'approved' و owner_employee_id لأي موظف آخر.
--     • projects_owner_update ... with check (owner = me) → بلا قيد على
--       الأعمدة أو الحالة، فيستطيع المالك عبر PostgREST المباشر ضبط
--       approval_status='approved' متجاوزاً فحص current_is_full_access()
--       داخل approve_project().
--     كل كتابات العميل (ويب + موبايل) تمر عبر RPCs فقط — لا وصول مباشر
--     للجداول — لذا نحذف سياسات التعديل المباشر ونُبقي القراءة فقط.
--
-- (2) P0 — 0522 أزالت `SET search_path` من دالتي SECURITY DEFINER.
--     دالة SECDEF بلا search_path مثبّت = ناقل تصعيد صلاحيات كلاسيكي
--     (اختطاف المعاملات/الدوال غير المؤهَّلة عبر مخطط يسبق public).
--     السبب المذكور («يربك ذاكرة مخطط PostgREST») غير صحيح — SET search_path
--     لا علاقة له بذاكرة PostgREST؛ لتحديثها استخدم NOTIFY pgrst, 'reload schema'.
--
-- (3) P1 — get_association_project_detail لم تُرجع عدّادات الخطوات الأربعة
--     بينما عقد Zod (associationProjectDetailSchema.project) يفرضها →
--     ZodError عند كل فتح للوحة التفاصيل.
--
-- (4) P1 — get_association_projects فقدت STABLE في 0521/0522.
--
-- (5) P1 — create_association_project_admin بلا أي تفويض وتقبل
--     p_owner_employee_id بلا تحقق → إنشاء مشروع باسم موظف آخر.
--
-- (6) ترتيب مقصود: هذه الـ migration يجب أن تبقى **بعد**
--     0524_nuclear_fix_association_projects.sql — تلك تُسقط وتُعيد إنشاء
--     get_association_projects بلا STABLE ومع `order by` خارج jsonb_agg
--     (يفشل 42803 وقت التشغيل). أي إعادة ترقيم تضعها بعد هذا الملف
--     تُعيد فتح الثغرة وتكسر الدالة.
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════
-- 1. RLS: إزالة مسارات الكتابة المباشرة
-- ═══════════════════════════════════════════════

-- سياسات 0518 التي تسمح بالكتابة المباشرة عبر PostgREST.
-- الكتابة كلها تتم عبر RPCs من نوع SECURITY DEFINER (تتجاوز RLS كمالك للجدول)،
-- فحذف هذه السياسات لا يكسر أي مسار قائم ويغلق التجاوز.
drop policy if exists projects_insert_auth  on public.association_projects;
drop policy if exists projects_owner_update on public.association_projects;
drop policy if exists updates_owner_insert  on public.association_project_updates;
drop policy if exists steps_owner_insert    on public.association_project_steps;
drop policy if exists steps_owner_update    on public.association_project_steps;
drop policy if exists steps_owner_delete    on public.association_project_steps;

-- سياسات القراءة للمالك وسياسات full-access تبقى كما هي (من 0518):
--   projects_full_access / projects_owner_read
--   updates_full_access  / updates_owner_read
--   steps_full_access    / steps_owner_read

comment on table public.association_projects is
  '0526: الكتابة حصراً عبر RPCs المحصّنة؛ RLS يسمح بالقراءة فقط لغير full-access.';

-- ═══════════════════════════════════════════════
-- 2. get_association_projects — استبدال كنوني
--    يعيد STABLE + SET search_path مع إبقاء إصلاح d.name من 0521/0522
-- ═══════════════════════════════════════════════

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
      select jsonb_agg(jsonb_build_object(
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
      -- الترتيب داخل jsonb_agg لا بعد الاستعلام: `select jsonb_agg(..) .. order by p.col`
      -- يفشل بـ 42803 (عمود خارج GROUP BY) — عيب موروث من 0512 حجبه خطأ d.name_ar.
      order by
        case p.approval_status when 'pending_approval' then 0 when 'draft' then 1 else 2 end,
        case p.priority when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
        p.updated_at desc)
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
grant execute on function public.get_association_projects() to authenticated;

-- ═══════════════════════════════════════════════
-- 3. get_association_project_detail — استبدال كنوني
--    يعيد search_path + يضيف عدّادات الخطوات التي يفرضها عقد Zod
-- ═══════════════════════════════════════════════

create or replace function public.get_association_project_detail(p_project_id uuid)
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

  if not v_full then
    if v_emp is null or not exists (
      select 1 from public.association_projects
      where id = p_project_id and owner_employee_id = v_emp
    ) then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;
  end if;

  if not exists (select 1 from public.association_projects where id = p_project_id) then
    raise exception 'PROJECT_NOT_FOUND' using errcode = '42P01';
  end if;

  select jsonb_build_object(
    'project', (
      select jsonb_build_object(
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
        -- عدّادات الخطوات: يفرضها associationProjectListItemSchema المُعاد
        -- استخدامه داخل associationProjectDetailSchema.project (0524).
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
      from public.association_projects p
      join public.departments d on d.id = p.department_id
      join public.employees   e on e.id = p.owner_employee_id
      where p.id = p_project_id
    ),
    'steps', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',           s.id,
        'title',        s.title,
        'description',  s.description,
        'sortOrder',    s.sort_order,
        'status',       s.status,
        'dueDate',      s.due_date,
        'assigneeId',   s.assignee_employee_id,
        'assigneeName', ae.full_name_ar
      ) order by s.sort_order, s.created_at)
      from public.association_project_steps s
      left join public.employees ae on ae.id = s.assignee_employee_id
      where s.project_id = p_project_id
    ), '[]'::jsonb),
    'updates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',           u.id,
        'note',         u.note,
        'progress',     u.progress,
        'statusChange', u.status_change,
        'authorName',   ue.full_name_ar,
        'createdAt',    u.created_at
      ) order by u.created_at desc)
      from public.association_project_updates u
      join public.employees ue on ue.id = u.author_employee_id
      where u.project_id = p_project_id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_association_project_detail(uuid) from public, anon;
grant execute on function public.get_association_project_detail(uuid) to authenticated;

-- ═══════════════════════════════════════════════
-- 4. create_association_project_admin — فرض التفويض
--    غير full-access: يملك مشروعه فقط، ويبدأ دائماً draft
-- ═══════════════════════════════════════════════

create or replace function public.create_association_project_admin(
  p_code              text,
  p_name              text,
  p_description       text,
  p_department_id     uuid,
  p_owner_employee_id uuid,
  p_priority          text default 'medium',
  p_start_date        date default null,
  p_target_end_date   date default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id    uuid;
  v_emp   uuid;
  v_full  boolean;
  v_owner uuid;
begin
  v_emp  := public.current_employee_id();
  v_full := public.current_is_full_access();

  if not v_full and v_emp is null then
    raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode = '42501';
  end if;

  -- غير full-access لا يملك تعيين مشروع لموظف آخر.
  if v_full then
    v_owner := coalesce(p_owner_employee_id, v_emp);
  else
    if p_owner_employee_id is not null and p_owner_employee_id <> v_emp then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;
    v_owner := v_emp;
  end if;

  insert into public.association_projects (
    code, name, description, department_id, owner_employee_id,
    status, approval_status, priority, start_date, target_end_date, created_by
  ) values (
    p_code, p_name, p_description, p_department_id, v_owner,
    'planned', 'draft', p_priority, p_start_date, p_target_end_date, auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_association_project_admin(text,text,text,uuid,uuid,text,date,date) from public, anon;
grant execute on function public.create_association_project_admin(text,text,text,uuid,uuid,text,date,date) to authenticated;
