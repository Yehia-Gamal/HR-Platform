-- Migration 0033: ATS workbench, learning, document studio, scheduled reports and push delivery queue
-- All sensitive writes are exposed through SECURITY DEFINER RPCs with explicit permission checks.

create table if not exists public.learning_courses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title_ar text not null,
  title_en text,
  description text,
  category text not null default 'general',
  delivery_mode text not null default 'online' check (delivery_mode in ('online','onsite','hybrid','self_paced')),
  duration_minutes integer not null default 0 check (duration_minutes >= 0),
  mandatory boolean not null default false,
  passing_score numeric(5,2) check (passing_score is null or (passing_score >= 0 and passing_score <= 100)),
  validity_months integer check (validity_months is null or validity_months > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id) on delete set null
);

create table if not exists public.learning_course_sessions (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.learning_courses(id) on delete cascade,
  starts_at timestamptz,
  ends_at timestamptz,
  location_or_link text,
  capacity integer check (capacity is null or capacity > 0),
  instructor_name text,
  status text not null default 'scheduled' check (status in ('draft','scheduled','in_progress','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id) on delete set null
);

create table if not exists public.learning_enrollments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  course_id uuid not null references public.learning_courses(id) on delete restrict,
  session_id uuid references public.learning_course_sessions(id) on delete set null,
  status text not null default 'enrolled' check (status in ('enrolled','in_progress','completed','failed','cancelled','expired')),
  progress_percent integer not null default 0 check (progress_percent between 0 and 100),
  score numeric(5,2) check (score is null or (score >= 0 and score <= 100)),
  enrolled_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at date,
  certificate_path text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  unique (employee_id, course_id, session_id)
);

create table if not exists public.document_templates (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_ar text not null,
  name_en text,
  document_type text not null,
  body_template text not null,
  version integer not null default 1 check (version > 0),
  requires_employee_signature boolean not null default false,
  requires_manager_signature boolean not null default false,
  requires_hr_signature boolean not null default false,
  requires_executive_signature boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id) on delete set null
);

create table if not exists public.generated_documents (
  id uuid primary key default gen_random_uuid(),
  template_id uuid references public.document_templates(id) on delete set null,
  employee_id uuid references public.employees(id) on delete set null,
  reference_number text not null unique,
  title text not null,
  document_type text not null,
  template_version integer,
  payload jsonb not null default '{}'::jsonb,
  rendered_storage_path text,
  content_sha256 text,
  status text not null default 'draft' check (status in ('draft','pending_signatures','signed','issued','revoked','archived')),
  issued_at timestamptz,
  revoked_at timestamptz,
  revoke_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id) on delete set null
);

create table if not exists public.document_signature_requests (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.generated_documents(id) on delete cascade,
  signer_user_id uuid not null references auth.users(id) on delete cascade,
  signer_employee_id uuid references public.employees(id) on delete set null,
  signer_role text not null,
  sequence_no integer not null default 1 check (sequence_no > 0),
  status text not null default 'pending' check (status in ('pending','signed','declined','cancelled','expired')),
  requested_at timestamptz not null default now(),
  due_at timestamptz,
  signed_at timestamptz,
  signature_method text,
  signature_evidence jsonb not null default '{}'::jsonb,
  decline_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  unique (document_id, signer_user_id, signer_role)
);

create table if not exists public.scheduled_reports (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_ar text not null,
  report_type text not null,
  audience_scope text not null default 'self' check (audience_scope in ('self','direct_reports','department','branch','organization','selected_users')),
  audience_config jsonb not null default '{}'::jsonb,
  schedule_kind text not null check (schedule_kind in ('daily','weekly','monthly','manual')),
  timezone text not null default 'Africa/Cairo',
  run_hour smallint not null default 8 check (run_hour between 0 and 23),
  run_weekday smallint check (run_weekday is null or run_weekday between 0 and 6),
  run_monthday smallint check (run_monthday is null or run_monthday between 1 and 28),
  delivery_channels text[] not null default array['in_app']::text[],
  active boolean not null default true,
  next_run_at timestamptz,
  last_run_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id) on delete set null
);

create table if not exists public.report_runs (
  id uuid primary key default gen_random_uuid(),
  scheduled_report_id uuid references public.scheduled_reports(id) on delete set null,
  report_type text not null,
  period_start date,
  period_end date,
  audience_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued','running','completed','failed','cancelled')),
  result_storage_path text,
  result_summary jsonb not null default '{}'::jsonb,
  idempotency_key text not null unique,
  attempts integer not null default 0,
  started_at timestamptz,
  completed_at timestamptz,
  error_detail text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

create table if not exists public.notification_jobs (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid references public.notifications(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  channel text not null default 'push' check (channel in ('push','in_app','email','sms')),
  status text not null default 'queued' check (status in ('queued','processing','sent','failed','cancelled')),
  available_at timestamptz not null default now(),
  attempts integer not null default 0,
  locked_at timestamptz,
  locked_by text,
  last_error text,
  sent_at timestamptz,
  idempotency_key text not null unique,
  created_at timestamptz not null default now()
);

alter table public.push_subscriptions add column if not exists platform text;
alter table public.push_subscriptions add column if not exists fcm_token text;
alter table public.push_subscriptions add column if not exists app_version text;
alter table public.push_subscriptions add column if not exists locale text not null default 'ar';
create unique index if not exists ux_push_subscriptions_fcm on public.push_subscriptions(user_id, fcm_token) where fcm_token is not null;

create index if not exists ix_learning_enrollments_employee on public.learning_enrollments(employee_id, status);
create index if not exists ix_learning_sessions_course on public.learning_course_sessions(course_id, starts_at);
create index if not exists ix_signature_requests_signer on public.document_signature_requests(signer_user_id, status);
create index if not exists ix_scheduled_reports_due on public.scheduled_reports(next_run_at) where active;
create index if not exists ix_notification_jobs_due on public.notification_jobs(status, available_at);

-- Consistent updated_at triggers.
do $$
declare t text;
begin
  foreach t in array array['learning_courses','learning_course_sessions','learning_enrollments','document_templates','generated_documents','document_signature_requests','scheduled_reports'] loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I', t, t);
    execute format('create trigger trg_%I_updated_at before update on public.%I for each row execute function public.tg_set_updated_at()', t, t);
  end loop;
end $$;

-- RLS.
do $$
declare t text;
begin
  foreach t in array array['learning_courses','learning_course_sessions','learning_enrollments','document_templates','generated_documents','document_signature_requests','scheduled_reports','report_runs','notification_jobs'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

create policy learning_courses_read on public.learning_courses for select to authenticated using (active or public.current_is_full_access() or public.has_permission('learning.course.manage'));
create policy learning_courses_manage on public.learning_courses for all to authenticated using (public.current_is_full_access() or public.has_permission('learning.course.manage')) with check (public.current_is_full_access() or public.has_permission('learning.course.manage'));
create policy learning_sessions_read on public.learning_course_sessions for select to authenticated using (true);
create policy learning_sessions_manage on public.learning_course_sessions for all to authenticated using (public.current_is_full_access() or public.has_permission('learning.course.manage')) with check (public.current_is_full_access() or public.has_permission('learning.course.manage'));
create policy learning_enrollments_read on public.learning_enrollments for select to authenticated using (public.current_is_full_access() or public.has_permission('learning.enrollment.manage') or public.can_access_employee(employee_id));
create policy learning_enrollments_manage on public.learning_enrollments for all to authenticated using (public.current_is_full_access() or public.has_permission('learning.enrollment.manage')) with check (public.current_is_full_access() or public.has_permission('learning.enrollment.manage'));
create policy document_templates_read on public.document_templates for select to authenticated using (active or public.current_is_full_access() or public.has_permission('documents.template.manage'));
create policy document_templates_manage on public.document_templates for all to authenticated using (public.current_is_full_access() or public.has_permission('documents.template.manage')) with check (public.current_is_full_access() or public.has_permission('documents.template.manage'));
create policy generated_documents_read on public.generated_documents for select to authenticated using (public.current_is_full_access() or public.has_permission('documents.generated.manage') or public.can_access_employee(employee_id));
create policy generated_documents_manage on public.generated_documents for all to authenticated using (public.current_is_full_access() or public.has_permission('documents.generated.manage')) with check (public.current_is_full_access() or public.has_permission('documents.generated.manage'));
create policy signature_requests_read on public.document_signature_requests for select to authenticated using (signer_user_id = auth.uid() or public.current_is_full_access() or public.has_permission('documents.signature.manage'));
create policy signature_requests_manage on public.document_signature_requests for all to authenticated using (public.current_is_full_access() or public.has_permission('documents.signature.manage')) with check (public.current_is_full_access() or public.has_permission('documents.signature.manage'));
create policy scheduled_reports_read on public.scheduled_reports for select to authenticated using (public.current_is_full_access() or public.has_permission('reports.schedule.manage'));
create policy scheduled_reports_manage on public.scheduled_reports for all to authenticated using (public.current_is_full_access() or public.has_permission('reports.schedule.manage')) with check (public.current_is_full_access() or public.has_permission('reports.schedule.manage'));
create policy report_runs_read on public.report_runs for select to authenticated using (public.current_is_full_access() or public.has_permission('reports.schedule.manage'));
create policy notification_jobs_no_client on public.notification_jobs for select to authenticated using (public.current_is_full_access() or public.has_permission('system.notifications.monitor'));

-- Permission seeds are idempotent and use the current permission catalog shape.
insert into public.permissions (code, module, resource, action, description, risk_level, is_sensitive)
values
 ('learning.course.manage','learning','course','manage','إنشاء وإدارة الدورات والجلسات','sensitive',false),
 ('learning.enrollment.manage','learning','enrollment','manage','تسجيل الموظفين ومتابعة الإكمال','sensitive',false),
 ('documents.template.manage','documents','template','manage','إدارة قوالب الخطابات والعقود','sensitive',true),
 ('documents.generated.manage','documents','generated','manage','توليد وإصدار وإلغاء المستندات','critical',true),
 ('documents.signature.manage','documents','signature','manage','إنشاء ومتابعة طلبات التوقيع','critical',true),
 ('reports.schedule.manage','reports','schedule','manage','جدولة التقارير ومتابعة التشغيل','critical',true),
 ('system.notifications.monitor','system','notifications','monitor','متابعة طابور الإشعارات والتسليم','critical',true)
on conflict (code) do update set description=excluded.description, risk_level=excluded.risk_level, is_sensitive=excluded.is_sensitive;

create or replace function public.queue_notification_jobs()
returns trigger language plpgsql security definer set search_path=public,auth as $$
begin
  insert into public.notification_jobs(notification_id,recipient_user_id,channel,idempotency_key)
  values(new.id,new.recipient_user_id,'in_app',new.id::text||':in_app')
  on conflict(idempotency_key) do nothing;
  if exists(select 1 from public.push_subscriptions where user_id=new.recipient_user_id and is_active) then
    insert into public.notification_jobs(notification_id,recipient_user_id,channel,idempotency_key)
    values(new.id,new.recipient_user_id,'push',new.id::text||':push')
    on conflict(idempotency_key) do nothing;
  end if;
  return new;
end $$;

drop trigger if exists trg_notifications_queue_jobs on public.notifications;
create trigger trg_notifications_queue_jobs after insert on public.notifications for each row execute function public.queue_notification_jobs();

create or replace function public.get_learning_admin_catalog()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['learning.course.manage','learning.enrollment.manage'])) then raise exception 'FORBIDDEN'; end if;
  return jsonb_build_object(
    'courses', coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'code',c.code,'title',c.title_ar,'category',c.category,'deliveryMode',c.delivery_mode,'durationMinutes',c.duration_minutes,'mandatory',c.mandatory,'active',c.active,'enrollments',(select count(*) from public.learning_enrollments e where e.course_id=c.id),'completed',(select count(*) from public.learning_enrollments e where e.course_id=c.id and e.status='completed')) order by c.created_at desc) from public.learning_courses c),'[]'::jsonb),
    'enrollments', coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'employeeId',e.employee_id,'employeeName',emp.full_name_ar,'employeeCode',emp.employee_code,'courseId',e.course_id,'courseTitle',c.title_ar,'status',e.status,'progress',e.progress_percent,'score',e.score,'enrolledAt',e.enrolled_at,'completedAt',e.completed_at,'expiresAt',e.expires_at) order by e.enrolled_at desc) from public.learning_enrollments e join public.employees emp on emp.id=e.employee_id join public.learning_courses c on c.id=e.course_id),'[]'::jsonb),
    'employees', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',full_name_ar,'code',employee_code) order by full_name_ar) from public.employees where is_active and not is_deleted),'[]'::jsonb),
    'lastUpdatedAt', now()
  );
end $$;

create or replace function public.upsert_learning_course_admin(p_id uuid,p_code text,p_title_ar text,p_title_en text,p_description text,p_category text,p_delivery_mode text,p_duration_minutes integer,p_mandatory boolean,p_passing_score numeric,p_validity_months integer,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('learning.course.manage')) then raise exception 'FORBIDDEN'; end if;
  if nullif(trim(p_code),'') is null or nullif(trim(p_title_ar),'') is null then raise exception 'CODE_AND_TITLE_REQUIRED'; end if;
  insert into public.learning_courses(id,code,title_ar,title_en,description,category,delivery_mode,duration_minutes,mandatory,passing_score,validity_months,active,created_by)
  values(coalesce(p_id,gen_random_uuid()),upper(trim(p_code)),trim(p_title_ar),nullif(trim(p_title_en),''),nullif(trim(p_description),''),coalesce(nullif(trim(p_category),''),'general'),p_delivery_mode,greatest(coalesce(p_duration_minutes,0),0),coalesce(p_mandatory,false),p_passing_score,p_validity_months,coalesce(p_active,true),auth.uid())
  on conflict(id) do update set code=excluded.code,title_ar=excluded.title_ar,title_en=excluded.title_en,description=excluded.description,category=excluded.category,delivery_mode=excluded.delivery_mode,duration_minutes=excluded.duration_minutes,mandatory=excluded.mandatory,passing_score=excluded.passing_score,validity_months=excluded.validity_months,active=excluded.active,updated_at=now()
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.enroll_employee_course_admin(p_employee_id uuid,p_course_id uuid,p_session_id uuid default null)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('learning.enrollment.manage')) then raise exception 'FORBIDDEN'; end if;
  if not exists(select 1 from public.employees where id=p_employee_id and is_active and not is_deleted) then raise exception 'EMPLOYEE_NOT_ACTIVE'; end if;
  if not exists(select 1 from public.learning_courses where id=p_course_id and active) then raise exception 'COURSE_NOT_ACTIVE'; end if;
  insert into public.learning_enrollments(employee_id,course_id,session_id,created_by) values(p_employee_id,p_course_id,p_session_id,auth.uid())
  on conflict(employee_id,course_id,session_id) do update set status='enrolled',progress_percent=0,score=null,completed_at=null,updated_at=now()
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.transition_learning_enrollment(p_enrollment_id uuid,p_status text,p_progress integer default null,p_score numeric default null)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v public.learning_enrollments%rowtype; v_emp uuid:=public.current_employee_id();
begin
  select * into v from public.learning_enrollments where id=p_enrollment_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if not (public.current_is_full_access() or public.has_permission('learning.enrollment.manage') or v.employee_id=v_emp) then raise exception 'FORBIDDEN'; end if;
  if p_status not in ('enrolled','in_progress','completed','failed','cancelled') then raise exception 'INVALID_STATUS'; end if;
  update public.learning_enrollments set status=p_status,progress_percent=case when p_status='completed' then 100 else coalesce(p_progress,progress_percent) end,score=coalesce(p_score,score),completed_at=case when p_status='completed' then now() else completed_at end,updated_at=now() where id=p_enrollment_id returning * into v;
  return jsonb_build_object('id',v.id,'status',v.status,'progress',v.progress_percent,'completedAt',v.completed_at);
end $$;

create or replace function public.get_my_learning_catalog()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_emp uuid:=public.current_employee_id();
begin
  if v_emp is null then raise exception 'EMPLOYEE_CONTEXT_REQUIRED'; end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'courseId',c.id,'title',c.title_ar,'category',c.category,'deliveryMode',c.delivery_mode,'durationMinutes',c.duration_minutes,'mandatory',c.mandatory,'status',e.status,'progress',e.progress_percent,'score',e.score,'completedAt',e.completed_at,'expiresAt',e.expires_at) order by e.enrolled_at desc) from public.learning_enrollments e join public.learning_courses c on c.id=e.course_id where e.employee_id=v_emp),'[]'::jsonb),'lastUpdatedAt',now());
end $$;

create or replace function public.get_document_studio_catalog()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['documents.template.manage','documents.generated.manage','documents.signature.manage'])) then raise exception 'FORBIDDEN'; end if;
  return jsonb_build_object(
   'templates',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name_ar,'documentType',document_type,'version',version,'active',active,'requiresEmployeeSignature',requires_employee_signature,'requiresManagerSignature',requires_manager_signature,'requiresHrSignature',requires_hr_signature,'requiresExecutiveSignature',requires_executive_signature) order by name_ar) from public.document_templates),'[]'::jsonb),
   'documents',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'referenceNumber',d.reference_number,'title',d.title,'documentType',d.document_type,'employeeId',d.employee_id,'employeeName',e.full_name_ar,'status',d.status,'createdAt',d.created_at,'issuedAt',d.issued_at,'pendingSignatures',(select count(*) from public.document_signature_requests s where s.document_id=d.id and s.status='pending')) order by d.created_at desc) from public.generated_documents d left join public.employees e on e.id=d.employee_id),'[]'::jsonb),
   'lastUpdatedAt',now());
end $$;

create or replace function public.upsert_document_template_admin(p_id uuid,p_code text,p_name_ar text,p_document_type text,p_body_template text,p_requires_employee boolean,p_requires_manager boolean,p_requires_hr boolean,p_requires_executive boolean,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid;
begin
 if not (public.current_is_full_access() or public.has_permission('documents.template.manage')) then raise exception 'FORBIDDEN'; end if;
 insert into public.document_templates(id,code,name_ar,document_type,body_template,requires_employee_signature,requires_manager_signature,requires_hr_signature,requires_executive_signature,active,created_by)
 values(coalesce(p_id,gen_random_uuid()),upper(trim(p_code)),trim(p_name_ar),trim(p_document_type),p_body_template,coalesce(p_requires_employee,false),coalesce(p_requires_manager,false),coalesce(p_requires_hr,false),coalesce(p_requires_executive,false),coalesce(p_active,true),auth.uid())
 on conflict(id) do update set code=excluded.code,name_ar=excluded.name_ar,document_type=excluded.document_type,body_template=excluded.body_template,version=public.document_templates.version+1,requires_employee_signature=excluded.requires_employee_signature,requires_manager_signature=excluded.requires_manager_signature,requires_hr_signature=excluded.requires_hr_signature,requires_executive_signature=excluded.requires_executive_signature,active=excluded.active,updated_at=now() returning id into v_id;
 return v_id;
end $$;

create or replace function public.get_report_scheduler_catalog()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
 if not (public.current_is_full_access() or public.has_permission('reports.schedule.manage')) then raise exception 'FORBIDDEN'; end if;
 return jsonb_build_object('schedules',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name_ar,'reportType',report_type,'audienceScope',audience_scope,'scheduleKind',schedule_kind,'timezone',timezone,'runHour',run_hour,'runWeekday',run_weekday,'runMonthday',run_monthday,'deliveryChannels',delivery_channels,'active',active,'nextRunAt',next_run_at,'lastRunAt',last_run_at) order by created_at desc) from public.scheduled_reports),'[]'::jsonb),'runs',coalesce((select jsonb_agg(jsonb_build_object('id',id,'reportType',report_type,'status',status,'periodStart',period_start,'periodEnd',period_end,'attempts',attempts,'createdAt',created_at,'completedAt',completed_at,'errorDetail',error_detail) order by created_at desc) from (select * from public.report_runs order by created_at desc limit 100) r),'[]'::jsonb),'notificationQueue',jsonb_build_object('queued',(select count(*) from public.notification_jobs where status='queued'),'failed',(select count(*) from public.notification_jobs where status='failed')),'lastUpdatedAt',now());
end $$;

create or replace function public.upsert_scheduled_report_admin(p_id uuid,p_code text,p_name_ar text,p_report_type text,p_audience_scope text,p_schedule_kind text,p_run_hour smallint,p_run_weekday smallint,p_run_monthday smallint,p_delivery_channels text[],p_active boolean)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_next timestamptz;
begin
 if not (public.current_is_full_access() or public.has_permission('reports.schedule.manage')) then raise exception 'FORBIDDEN'; end if;
 v_next:=case when p_schedule_kind='daily' then date_trunc('day',now() at time zone 'Africa/Cairo') + make_interval(hours=>p_run_hour) + interval '1 day' when p_schedule_kind='weekly' then now()+interval '7 days' when p_schedule_kind='monthly' then now()+interval '1 month' else null end;
 insert into public.scheduled_reports(id,code,name_ar,report_type,audience_scope,schedule_kind,run_hour,run_weekday,run_monthday,delivery_channels,active,next_run_at,created_by)
 values(coalesce(p_id,gen_random_uuid()),upper(trim(p_code)),trim(p_name_ar),p_report_type,p_audience_scope,p_schedule_kind,p_run_hour,p_run_weekday,p_run_monthday,coalesce(p_delivery_channels,array['in_app']::text[]),coalesce(p_active,true),v_next,auth.uid())
 on conflict(id) do update set code=excluded.code,name_ar=excluded.name_ar,report_type=excluded.report_type,audience_scope=excluded.audience_scope,schedule_kind=excluded.schedule_kind,run_hour=excluded.run_hour,run_weekday=excluded.run_weekday,run_monthday=excluded.run_monthday,delivery_channels=excluded.delivery_channels,active=excluded.active,next_run_at=excluded.next_run_at,updated_at=now() returning id into v_id;
 return v_id;
end $$;

create or replace function public.queue_due_scheduled_reports(p_now timestamptz default now())
returns integer language plpgsql security definer set search_path=public,auth as $$
declare v_count integer:=0; r record; v_key text;
begin
 if auth.role() <> 'service_role' and not public.current_is_full_access() then raise exception 'FORBIDDEN'; end if;
 for r in select * from public.scheduled_reports where active and next_run_at is not null and next_run_at<=p_now for update skip locked loop
   v_key:=r.id::text||':'||to_char(r.next_run_at,'YYYYMMDDHH24MI');
   insert into public.report_runs(scheduled_report_id,report_type,audience_snapshot,status,idempotency_key,created_by) values(r.id,r.report_type,jsonb_build_object('scope',r.audience_scope,'config',r.audience_config),'queued',v_key,auth.uid()) on conflict(idempotency_key) do nothing;
   if found then v_count:=v_count+1; end if;
   update public.scheduled_reports set last_run_at=r.next_run_at,next_run_at=case r.schedule_kind when 'daily' then r.next_run_at+interval '1 day' when 'weekly' then r.next_run_at+interval '7 days' when 'monthly' then r.next_run_at+interval '1 month' else null end,updated_at=now() where id=r.id;
 end loop;
 return v_count;
end $$;

create or replace function public.get_recruitment_workbench_catalog()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
 if not (public.current_is_full_access() or public.has_any_permission(array['recruitment.requisition.read','recruitment.candidate.read','recruitment.candidate.manage'])) then raise exception 'FORBIDDEN'; end if;
 return jsonb_build_object(
  'requisitions',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'title',r.title,'departmentId',r.department_id,'departmentName',d.name,'headcount',r.headcount,'status',r.status,'createdAt',r.created_at) order by r.created_at desc) from public.job_requisitions r join public.departments d on d.id=r.department_id),'[]'::jsonb),
  'postings',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'requisitionId',p.requisition_id,'title',r.title,'slug',p.public_slug,'visibility',p.visibility,'status',p.status,'publishedAt',p.published_at,'closesAt',p.closes_at) order by p.created_at desc) from public.job_postings p join public.job_requisitions r on r.id=p.requisition_id),'[]'::jsonb),
  'applications',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'candidateId',c.id,'candidateName',c.full_name,'postingId',p.id,'jobTitle',r.title,'status',a.status,'stageId',s.current_stage_id,'stageName',st.name,'appliedAt',a.applied_at,'assigneeId',s.assignee_id) order by a.applied_at desc) from public.applications a join public.candidates c on c.id=a.candidate_id join public.job_postings p on p.id=a.posting_id join public.job_requisitions r on r.id=p.requisition_id left join public.application_current_state s on s.application_id=a.id left join public.pipeline_stages st on st.id=s.current_stage_id),'[]'::jsonb),
  'candidates',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',full_name,'email',email_norm,'phone',phone_norm,'source',source,'tags',tags,'createdAt',created_at) order by created_at desc) from public.candidates),'[]'::jsonb),
  'stages',coalesce((select jsonb_agg(jsonb_build_object('id',id,'postingId',posting_id,'name',name,'orderIndex',order_index,'slaDays',sla_days) order by posting_id,order_index) from public.pipeline_stages),'[]'::jsonb),
  'interviews',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'applicationId',i.application_id,'candidateName',c.full_name,'mode',i.mode,'scheduledAt',i.scheduled_at,'status',i.status,'locationOrLink',i.location_or_link) order by i.scheduled_at nulls last) from public.interviews i join public.applications a on a.id=i.application_id join public.candidates c on c.id=a.candidate_id),'[]'::jsonb),
  'offers',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'applicationId',o.application_id,'candidateName',c.full_name,'title',o.title,'status',o.status,'startDate',o.start_date,'expiresAt',o.expires_at,'version',o.version) order by o.created_at desc) from public.job_offers o join public.applications a on a.id=o.application_id join public.candidates c on c.id=a.candidate_id),'[]'::jsonb),
  'lastUpdatedAt',now());
end $$;

create or replace function public.move_application_stage_admin(p_application_id uuid,p_to_stage_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_current public.application_current_state%rowtype; v_emp uuid:=public.current_employee_id();
begin
 if not (public.current_is_full_access() or public.has_permission('recruitment.candidate.manage')) then raise exception 'FORBIDDEN'; end if;
 if not exists(select 1 from public.pipeline_stages st join public.applications a on a.posting_id=st.posting_id where st.id=p_to_stage_id and a.id=p_application_id) then raise exception 'STAGE_NOT_IN_POSTING'; end if;
 select * into v_current from public.application_current_state where application_id=p_application_id for update;
 if found then
  insert into public.application_stage_history(application_id,from_stage,to_stage,moved_by,reason,created_by) values(p_application_id,v_current.current_stage_id,p_to_stage_id,v_emp,nullif(trim(p_reason),''),auth.uid());
  update public.application_current_state set current_stage_id=p_to_stage_id,entered_stage_at=now(),updated_at=now() where application_id=p_application_id;
 else
  insert into public.application_current_state(application_id,current_stage_id,entered_stage_at,created_by) values(p_application_id,p_to_stage_id,now(),auth.uid());
  insert into public.application_stage_history(application_id,to_stage,moved_by,reason,created_by) values(p_application_id,p_to_stage_id,v_emp,nullif(trim(p_reason),''),auth.uid());
 end if;
 return jsonb_build_object('applicationId',p_application_id,'stageId',p_to_stage_id,'movedAt',now());
end $$;

grant execute on function public.get_learning_admin_catalog() to authenticated;
grant execute on function public.upsert_learning_course_admin(uuid,text,text,text,text,text,text,integer,boolean,numeric,integer,boolean) to authenticated;
grant execute on function public.enroll_employee_course_admin(uuid,uuid,uuid) to authenticated;
grant execute on function public.transition_learning_enrollment(uuid,text,integer,numeric) to authenticated;
grant execute on function public.get_my_learning_catalog() to authenticated;
grant execute on function public.get_document_studio_catalog() to authenticated;
grant execute on function public.upsert_document_template_admin(uuid,text,text,text,text,boolean,boolean,boolean,boolean,boolean) to authenticated;
grant execute on function public.get_report_scheduler_catalog() to authenticated;
grant execute on function public.upsert_scheduled_report_admin(uuid,text,text,text,text,text,smallint,smallint,smallint,text[],boolean) to authenticated;
grant execute on function public.get_recruitment_workbench_catalog() to authenticated;
grant execute on function public.move_application_stage_admin(uuid,uuid,text) to authenticated;
revoke execute on function public.queue_due_scheduled_reports(timestamptz) from public,anon,authenticated;
grant execute on function public.queue_due_scheduled_reports(timestamptz) to service_role;
