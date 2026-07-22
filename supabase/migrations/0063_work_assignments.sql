-- =====================================================================
-- 0063: وحدة تكليفات العمل — المأمورية / القافلة / الفاندي
-- =====================================================================
-- المرجع: المواصفة الرسمية (البنود 8،9،10،11،13،16،17،18،19،20).
-- المبدأ: تكليفات العمل عمل رسمي، لا تخصم من رصيد الإجازات ولا تُحتسب غيابًا.
--   جدولان مستقلان تمامًا عن محرك الطلبات/الإجازة كما في البند 19:
--     work_assignments            — رأس التكليف
--     work_assignment_participants — المشاركون + الحضور + التقرير
--   حالات مستقلة (البند 13) لا تستخدم حالة «إجازة معتمدة».
-- ملاحظة: الجداول القديمة missions / convoy_requests تبقى للأرشيف؛ الإنشاء
--   الجديد يمر عبر هذه الوحدة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) جدول رأس التكليف
-- ---------------------------------------------------------------------
create table if not exists public.work_assignments (
  id                 uuid primary key default gen_random_uuid(),
  assignment_number  bigint generated always as identity,
  assignment_type    text not null
                       check (assignment_type in ('MISSION','CONVOY','FUNDRAISING')),
  subtype            text,                          -- نوع فرعي (مأمورية إدارية/ميدانية...)
  title              text not null,
  description        text,
  status             text not null default 'DRAFT'
                       check (status in (
                         'DRAFT','SUBMITTED','PENDING_APPROVAL','APPROVED','REJECTED',
                         'IN_PROGRESS','COMPLETED','REPORT_PENDING','REPORT_SUBMITTED','CANCELLED'
                       )),
  created_by_employee_id uuid references public.employees(id) on delete set null, -- المدير المنشئ
  responsible_employee_id uuid references public.employees(id) on delete set null, -- المسؤول الميداني
  start_at           timestamptz not null,
  end_at             timestamptz not null,
  is_full_day        boolean not null default true,
  location           text,
  transport_mode     text,
  instructions       text,
  project_id         uuid,                          -- المشروع/الحملة المرتبطة (مرن)
  campaign_name      text,
  -- الفاندي: المستهدف المالي (لا يُخصم من رصيد أي شيء).
  target_amount      numeric(14,2),
  achieved_amount    numeric(14,2),
  -- الحضور/KPI: تكليف العمل يُحتسب يوم عمل، لا غياب.
  counts_as_work_day boolean not null default true,
  needs_report       boolean not null default false,
  report_due_at      timestamptz,
  decided_by         uuid references public.employees(id) on delete set null,
  decided_at         timestamptz,
  decision_comment   text,
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id),
  constraint ck_work_assignments_period check (end_at >= start_at)
);
comment on table public.work_assignments is
  'تكليفات العمل الرسمية (مأمورية/قافلة/فاندي). لا تخصم من رصيد الإجازات ولا تُحتسب غيابًا (البند 19).';

create index if not exists ix_work_assignments_type on public.work_assignments (assignment_type);
create index if not exists ix_work_assignments_status on public.work_assignments (status);
create index if not exists ix_work_assignments_creator on public.work_assignments (created_by_employee_id);
create index if not exists ix_work_assignments_responsible on public.work_assignments (responsible_employee_id);
create index if not exists ix_work_assignments_period on public.work_assignments (start_at, end_at);

drop trigger if exists trg_work_assignments_updated_at on public.work_assignments;
create trigger trg_work_assignments_updated_at
  before update on public.work_assignments
  for each row execute function public.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- 2) جدول المشاركين
-- ---------------------------------------------------------------------
create table if not exists public.work_assignment_participants (
  id                 uuid primary key default gen_random_uuid(),
  assignment_id      uuid not null references public.work_assignments(id) on delete cascade,
  employee_id        uuid not null references public.employees(id) on delete cascade,
  role_in_assignment text,
  attendance_status  text not null default 'assigned'
                       check (attendance_status in ('assigned','acknowledged','present','absent','completed')),
  arrived_at         timestamptz,
  left_at            timestamptz,
  report             text,
  outcome            text,
  achieved_amount    numeric(14,2),                 -- للفاندي: محقق كل مشارك
  acknowledged_at    timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id),
  unique(assignment_id, employee_id)
);
comment on table public.work_assignment_participants is
  'مشاركو تكليف العمل: الدور، حالة الحضور، أوقات الوصول/المغادرة، التقرير والنتيجة.';

create index if not exists ix_wa_participants_assignment on public.work_assignment_participants (assignment_id);
create index if not exists ix_wa_participants_employee on public.work_assignment_participants (employee_id);

drop trigger if exists trg_wa_participants_updated_at on public.work_assignment_participants;
create trigger trg_wa_participants_updated_at
  before update on public.work_assignment_participants
  for each row execute function public.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- 3) RLS (البند 20): لا كتابة مباشرة — عبر RPC فقط. القراءة مقيّدة بالوصول.
-- ---------------------------------------------------------------------
alter table public.work_assignments enable row level security;
alter table public.work_assignment_participants enable row level security;

drop policy if exists work_assignments_select on public.work_assignments;
create policy work_assignments_select on public.work_assignments
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array[
        'assignments.mission.manage','assignments.convoy.manage',
        'assignments.fundraising.manage','operations.mission.manage','operations.convoy.manage'])
    or created_by_employee_id = public.current_employee_id()
    or responsible_employee_id = public.current_employee_id()
    or exists (
      select 1 from public.work_assignment_participants p
      where p.assignment_id = id
        and (p.employee_id = public.current_employee_id()
             or public.can_access_employee(p.employee_id)))
  );

drop policy if exists work_assignment_participants_select on public.work_assignment_participants;
create policy work_assignment_participants_select on public.work_assignment_participants
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array[
        'assignments.mission.manage','assignments.convoy.manage','assignments.fundraising.manage'])
    or employee_id = public.current_employee_id()
    or public.can_access_employee(employee_id)
    or exists (select 1 from public.work_assignments a
               where a.id = assignment_id
                 and (a.created_by_employee_id = public.current_employee_id()
                      or a.responsible_employee_id = public.current_employee_id()))
  );

-- منع الكتابة المباشرة (P0): كل التعديلات عبر RPCs SECURITY DEFINER أدناه.
revoke insert, update, delete on public.work_assignments from authenticated;
revoke insert, update, delete on public.work_assignment_participants from authenticated;
-- المشارك يستطيع تأكيد الاطلاع/إرسال تقريره عبر RPC مخصص فقط.

-- ---------------------------------------------------------------------
-- 4) دالة صلاحية النوع + التحقق من فريق المدير.
-- ---------------------------------------------------------------------
create or replace function public.can_manage_assignment_type(p_type text)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select public.current_is_full_access()
    or case p_type
         when 'MISSION' then public.has_any_permission(array['assignments.mission.manage','operations.mission.manage'])
         when 'CONVOY' then public.has_any_permission(array['assignments.convoy.manage','operations.convoy.manage'])
         when 'FUNDRAISING' then public.has_permission('assignments.fundraising.manage')
         else false
       end;
$$;
revoke execute on function public.can_manage_assignment_type(text) from public;
grant execute on function public.can_manage_assignment_type(text) to authenticated, service_role;

-- 4b) صلاحية إدارة النوع على نطاق واسع (organization/department/branch) — تسمح
--     بالتكليف خارج الفريق المباشر (العمليات/السكرتير)، بخلاف المدير المباشر
--     الذي صلاحيته بنطاق direct_reports فيجب أن يكون الموظف تحته.
--     ملاحظة: has_permission يتجاهل النطاق، لذا نفحص role_permissions.scope مباشرة.
create or replace function public.can_manage_assignment_type_org_wide(p_type text)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select public.current_is_full_access()
    or exists (
      select 1
      from public.role_permissions rp
      join public.permissions pm on pm.id = rp.permission_id
      where rp.role_id = any (public.current_role_ids())
        and (rp.effective_from is null or rp.effective_from <= now())
        and (rp.effective_to   is null or rp.effective_to   >  now())
        and rp.scope in ('organization','department','branch')
        and pm.code = any (
          case p_type
            when 'MISSION' then array['assignments.mission.manage','operations.mission.manage']
            when 'CONVOY' then array['assignments.convoy.manage','operations.convoy.manage']
            when 'FUNDRAISING' then array['assignments.fundraising.manage']
            else array[]::text[]
          end)
    );
$$;
revoke execute on function public.can_manage_assignment_type_org_wide(text) from public;
grant execute on function public.can_manage_assignment_type_org_wide(text) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 5) RPC: إنشاء تكليف عمل (المدير/العمليات/السكرتير).
--    البند 20: منع تكليف موظف خارج الفريق دون صلاحية أوسع.
-- ---------------------------------------------------------------------
create or replace function public.create_work_assignment(
  p_assignment_type text,
  p_title text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_participant_ids uuid[],
  p_description text default null,
  p_location text default null,
  p_responsible_employee_id uuid default null,
  p_needs_report boolean default false,
  p_report_due_at timestamptz default null,
  p_payload jsonb default '{}'::jsonb
)
returns public.work_assignments
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.work_assignments;
  v_emp uuid;
  v_can_manage boolean;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
begin
  if v_me is null then raise exception 'no employee linked' using errcode = '42501'; end if;
  if p_assignment_type not in ('MISSION','CONVOY','FUNDRAISING') then
    raise exception 'invalid assignment type' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3 then
    raise exception 'title is required' using errcode = '22023';
  end if;
  if p_start_at is null or p_end_at is null or p_end_at < p_start_at then
    raise exception 'invalid assignment period' using errcode = '22023';
  end if;
  if p_participant_ids is null or array_length(p_participant_ids,1) is null then
    raise exception 'at least one participant is required' using errcode = '22023';
  end if;

  -- صلاحية الإدارة العامة (للقرار/الإلغاء): أي نطاق. أما التكليف خارج الفريق
  -- فيتطلب صلاحية بنطاق واسع (organization/department/branch) — المدير المباشر
  -- (direct_reports) يستطيع فقط تكليف من هم تحته.
  v_can_manage := public.can_manage_assignment_type_org_wide(p_assignment_type);

  -- البند 20: كل مشارك يجب أن يكون تحت المدير (can_access_employee) أو أن يملك
  -- المنشئ صلاحية إدارة هذا النوع بنطاق واسع (عمليات/سكرتير) للتكليف خارج الفريق.
  foreach v_emp in array p_participant_ids loop
    if not (v_can_manage or public.can_access_employee(v_emp)) then
      raise exception 'cannot assign employee outside your team without permission: %', v_emp
        using errcode = '42501';
    end if;
  end loop;

  insert into public.work_assignments(
    assignment_type, subtype, title, description, status,
    created_by_employee_id, responsible_employee_id, start_at, end_at,
    is_full_day, location, transport_mode, instructions, project_id, campaign_name,
    target_amount, needs_report, report_due_at, metadata, created_by)
  values(
    p_assignment_type, nullif(v_payload->>'subtype',''), trim(p_title), p_description,
    'APPROVED',   -- الإنشاء بواسطة المدير تكليف مباشر معتمد (البند 16).
    v_me, coalesce(p_responsible_employee_id, v_me), p_start_at, p_end_at,
    coalesce((v_payload->>'isFullDay')::boolean, true),
    p_location, nullif(v_payload->>'transportMode',''),
    nullif(v_payload->>'instructions',''),
    nullif(v_payload->>'projectId','')::uuid, nullif(v_payload->>'campaignName',''),
    nullif(v_payload->>'targetAmount','')::numeric,
    coalesce(p_needs_report,false), p_report_due_at, v_payload, auth.uid())
  returning * into v_row;

  -- المشاركون + إشعار كلٍّ منهم (البند 16: يصل إشعار ويظهر في التقويم).
  foreach v_emp in array p_participant_ids loop
    insert into public.work_assignment_participants(
      assignment_id, employee_id, role_in_assignment, created_by)
    values(v_row.id, v_emp, nullif(v_payload->>'roleInAssignment',''), auth.uid())
    on conflict(assignment_id, employee_id) do nothing;

    perform public.notify_employee(
      v_emp, 'تكليف عمل جديد',
      format('%s: %s', case v_row.assignment_type
                         when 'MISSION' then 'مأمورية'
                         when 'CONVOY' then 'قافلة'
                         else 'فاندي' end, v_row.title),
      'general', 'normal', 'work_assignments', v_row.id,
      jsonb_build_object('assignmentType', v_row.assignment_type,
                         'startAt', v_row.start_at, 'endAt', v_row.end_at));
  end loop;

  perform public.log_audit_event(
    'assignment.created', 'workflow', 'info', 'work_assignments', v_row.id,
    'إنشاء تكليف عمل', v_row.title,
    jsonb_build_object('type', v_row.assignment_type,
                       'participants', array_length(p_participant_ids,1)));
  return v_row;
end $$;
revoke execute on function public.create_work_assignment(text,text,timestamptz,timestamptz,uuid[],text,text,uuid,boolean,timestamptz,jsonb) from public;
grant execute on function public.create_work_assignment(text,text,timestamptz,timestamptz,uuid[],text,text,uuid,boolean,timestamptz,jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 6) RPC: قرار على تكليف (اعتماد/رفض) — للمخوّل بإدارة النوع.
-- ---------------------------------------------------------------------
create or replace function public.decide_work_assignment(
  p_assignment_id uuid,
  p_decision text,
  p_comment text default null
)
returns public.work_assignments
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_me uuid := public.current_employee_id(); v_row public.work_assignments; v_to text;
begin
  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision' using errcode = '22023';
  end if;
  select * into v_row from public.work_assignments where id = p_assignment_id for update;
  if not found then raise exception 'assignment not found' using errcode = 'P0002'; end if;
  if not (public.can_manage_assignment_type(v_row.assignment_type)
          or v_row.created_by_employee_id = v_me) then
    raise exception 'not authorized to decide this assignment' using errcode = '42501';
  end if;
  if v_row.status not in ('SUBMITTED','PENDING_APPROVAL','DRAFT') then
    raise exception 'assignment not in a decidable state (%)', v_row.status using errcode = '22023';
  end if;
  v_to := case when p_decision = 'approve' then 'APPROVED' else 'REJECTED' end;

  update public.work_assignments
    set status = v_to, decided_by = v_me, decided_at = now(),
        decision_comment = p_comment, updated_at = now()
    where id = p_assignment_id returning * into v_row;

  perform public.log_audit_event(
    'assignment.decided', 'workflow', 'info', 'work_assignments', p_assignment_id,
    'قرار على تكليف عمل', p_decision,
    jsonb_build_object('decision', p_decision, 'type', v_row.assignment_type));
  return v_row;
end $$;
revoke execute on function public.decide_work_assignment(uuid,text,text) from public;
grant execute on function public.decide_work_assignment(uuid,text,text) to authenticated;

-- ---------------------------------------------------------------------
-- 7) RPC: تأكيد اطلاع المشارك.
-- ---------------------------------------------------------------------
create or replace function public.acknowledge_assignment(p_assignment_id uuid)
returns public.work_assignment_participants
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_me uuid := public.current_employee_id(); v_row public.work_assignment_participants;
begin
  update public.work_assignment_participants
    set attendance_status = 'acknowledged', acknowledged_at = now(), updated_at = now()
    where assignment_id = p_assignment_id and employee_id = v_me
    returning * into v_row;
  if not found then raise exception 'not a participant' using errcode = '42501'; end if;
  return v_row;
end $$;
revoke execute on function public.acknowledge_assignment(uuid) from public;
grant execute on function public.acknowledge_assignment(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 8) RPC: إرسال تقرير تنفيذ التكليف (المشارك/المسؤول).
-- ---------------------------------------------------------------------
create or replace function public.submit_assignment_report(
  p_assignment_id uuid,
  p_report text,
  p_outcome text default null,
  p_achieved_amount numeric default null
)
returns public.work_assignment_participants
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_me uuid := public.current_employee_id(); v_row public.work_assignment_participants;
begin
  if length(trim(coalesce(p_report,''))) < 3 then
    raise exception 'report is required' using errcode = '22023';
  end if;
  update public.work_assignment_participants
    set report = p_report, outcome = p_outcome, achieved_amount = p_achieved_amount,
        attendance_status = 'completed', updated_at = now()
    where assignment_id = p_assignment_id and employee_id = v_me
    returning * into v_row;
  if not found then raise exception 'not a participant' using errcode = '42501'; end if;

  update public.work_assignments
    set status = 'REPORT_SUBMITTED', updated_at = now()
    where id = p_assignment_id and needs_report = true and status in ('APPROVED','IN_PROGRESS','COMPLETED','REPORT_PENDING');

  perform public.log_audit_event(
    'assignment.report.submitted', 'workflow', 'info', 'work_assignments', p_assignment_id,
    'إرسال تقرير تنفيذ تكليف', null,
    jsonb_build_object('employeeId', v_me, 'achievedAmount', p_achieved_amount));
  return v_row;
end $$;
revoke execute on function public.submit_assignment_report(uuid,text,text,numeric) from public;
grant execute on function public.submit_assignment_report(uuid,text,text,numeric) to authenticated;

-- ---------------------------------------------------------------------
-- 9) RPC: إلغاء تكليف.
-- ---------------------------------------------------------------------
create or replace function public.cancel_work_assignment(
  p_assignment_id uuid,
  p_reason text default null
)
returns public.work_assignments
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_me uuid := public.current_employee_id(); v_row public.work_assignments;
begin
  select * into v_row from public.work_assignments where id = p_assignment_id for update;
  if not found then raise exception 'assignment not found' using errcode = 'P0002'; end if;
  if not (public.can_manage_assignment_type(v_row.assignment_type)
          or v_row.created_by_employee_id = v_me) then
    raise exception 'not authorized to cancel this assignment' using errcode = '42501';
  end if;
  if v_row.status in ('COMPLETED','CANCELLED') then
    raise exception 'assignment already closed (%)', v_row.status using errcode = '22023';
  end if;
  update public.work_assignments
    set status = 'CANCELLED', decision_comment = p_reason, updated_at = now()
    where id = p_assignment_id returning * into v_row;

  perform public.log_audit_event(
    'assignment.cancelled', 'workflow', 'warning', 'work_assignments', p_assignment_id,
    'إلغاء تكليف عمل', p_reason, jsonb_build_object('type', v_row.assignment_type));
  return v_row;
end $$;
revoke execute on function public.cancel_work_assignment(uuid,text) from public;
grant execute on function public.cancel_work_assignment(uuid,text) to authenticated;

-- ---------------------------------------------------------------------
-- 10) RPC للقراءة: صندوق تكليفاتي/تكليفات فريقي.
-- ---------------------------------------------------------------------
create or replace function public.get_work_assignments_inbox(
  p_scope text default 'mine',   -- 'mine' | 'team'
  p_limit integer default 100
)
returns setof public.work_assignments
language sql stable security definer set search_path = public, pg_temp
as $$
  select a.* from public.work_assignments a
  where (
    p_scope = 'team' and (
      a.created_by_employee_id = public.current_employee_id()
      or a.responsible_employee_id = public.current_employee_id()
      or public.can_manage_assignment_type(a.assignment_type)
      or exists (select 1 from public.work_assignment_participants p
                 where p.assignment_id = a.id and public.can_access_employee(p.employee_id)))
  ) or (
    p_scope <> 'team' and exists (
      select 1 from public.work_assignment_participants p
      where p.assignment_id = a.id and p.employee_id = public.current_employee_id())
  )
  order by a.start_at desc
  limit greatest(1, least(p_limit, 500));
$$;
revoke execute on function public.get_work_assignments_inbox(text,integer) from public;
grant execute on function public.get_work_assignments_inbox(text,integer) to authenticated;

-- =====================================================================
-- نهاية Migration 0063
-- =====================================================================
