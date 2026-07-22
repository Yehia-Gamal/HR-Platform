-- Migration 0028: published rosters, attendance period closing, corrections and overtime
begin;

insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive)
values
 ('attendance.roster.read','attendance','roster','read','قراءة جداول الورديات المنشورة','normal',false),
 ('attendance.roster.manage','attendance','roster','manage','إنشاء ونشر جداول الورديات','sensitive',true),
 ('attendance.period.close','attendance','period','close','إغلاق فترة حضور شهرية','critical',true),
 ('attendance.period.unlock','attendance','period','unlock','إعادة فتح فترة حضور مغلقة','critical',true),
 ('attendance.correction.review','attendance','correction','review','مراجعة تصحيحات الحضور','sensitive',true),
 ('attendance.overtime.approve','attendance','overtime','approve','اعتماد ساعات العمل الإضافي','sensitive',true)
on conflict(code) do nothing;

create table if not exists public.attendance_periods (
  id uuid primary key default gen_random_uuid(),
  period_month date not null,
  legal_entity_id uuid references public.legal_entities(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,
  status text not null default 'open' check(status in ('open','closing','closed','unlocked')),
  closed_at timestamptz,
  closed_by uuid references public.employees(id) on delete set null,
  unlocked_at timestamptz,
  unlocked_by uuid references public.employees(id) on delete set null,
  unlock_reason text,
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id),
  unique(period_month,legal_entity_id,branch_id),
  check(period_month=date_trunc('month',period_month)::date)
);

create table if not exists public.work_rosters (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  period_start date not null,
  period_end date not null,
  department_id uuid references public.departments(id) on delete set null,
  team_id uuid references public.teams(id) on delete set null,
  branch_id uuid references public.branches(id) on delete set null,
  status text not null default 'draft' check(status in ('draft','published','superseded','cancelled')),
  published_at timestamptz,
  published_by uuid references public.employees(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id),
  check(period_end>=period_start)
);

create table if not exists public.roster_days (
  id uuid primary key default gen_random_uuid(),
  roster_id uuid not null references public.work_rosters(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  work_date date not null,
  shift_id uuid references public.shifts(id) on delete set null,
  work_site_id uuid references public.work_sites(id) on delete set null,
  geofence_id uuid references public.geofences(id) on delete set null,
  day_status text not null default 'scheduled' check(day_status in ('scheduled','rest','holiday','leave','mission','cancelled')),
  start_override time,
  end_override time,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id),
  unique(roster_id,employee_id,work_date)
);
create unique index if not exists ux_published_roster_employee_day on public.roster_days(employee_id,work_date)
where day_status<>'cancelled';

create table if not exists public.attendance_corrections (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  attendance_daily_id uuid references public.attendance_daily(id) on delete set null,
  work_date date not null,
  correction_type text not null check(correction_type in ('missing_check_in','missing_check_out','wrong_time','wrong_status','mission','leave','other')),
  requested_check_in timestamptz,
  requested_check_out timestamptz,
  requested_status text,
  reason text not null,
  attachment_path text,
  status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
  reviewed_by uuid references public.employees(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);

create table if not exists public.overtime_records (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  work_date date not null,
  attendance_daily_id uuid references public.attendance_daily(id) on delete set null,
  requested_minutes integer not null check(requested_minutes>0),
  approved_minutes integer check(approved_minutes>=0),
  reason text,
  status text not null default 'pending' check(status in ('pending','approved','rejected','paid','cancelled')),
  approved_by uuid references public.employees(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id),
  unique(employee_id,work_date,attendance_daily_id)
);

create index if not exists ix_rosters_period on public.work_rosters(period_start,period_end,status);
create index if not exists ix_roster_days_employee_date on public.roster_days(employee_id,work_date);
create index if not exists ix_attendance_corrections_status on public.attendance_corrections(status,work_date);
create index if not exists ix_overtime_records_status on public.overtime_records(status,work_date);

do $$
declare t text;
begin
  foreach t in array array['attendance_periods','work_rosters','roster_days','attendance_corrections','overtime_records'] loop
    execute format('drop trigger if exists trg_%1$s_updated_at on public.%1$s',t);
    execute format('create trigger trg_%1$s_updated_at before update on public.%1$s for each row execute function public.tg_set_updated_at()',t);
    execute format('alter table public.%I enable row level security',t);
  end loop;
end $$;


drop policy if exists attendance_periods_read on public.attendance_periods;
create policy attendance_periods_read on public.attendance_periods for select to authenticated using (
 public.current_is_full_access() or public.has_any_permission(array['attendance.record.read','attendance.period.close','attendance.period.unlock'])
);
drop policy if exists work_rosters_read on public.work_rosters;
create policy work_rosters_read on public.work_rosters for select to authenticated using (
 public.current_is_full_access() or public.has_permission('attendance.roster.read') or public.has_permission('attendance.roster.manage')
);
drop policy if exists roster_days_read on public.roster_days;
create policy roster_days_read on public.roster_days for select to authenticated using (
 employee_id=public.current_employee_id() or public.can_access_employee(employee_id,'attendance.roster.read')
 or public.current_is_full_access() or public.has_permission('attendance.roster.manage')
);
drop policy if exists attendance_corrections_read on public.attendance_corrections;
create policy attendance_corrections_read on public.attendance_corrections for select to authenticated using (
 employee_id=public.current_employee_id() or public.can_access_employee(employee_id,'attendance.correction.review')
 or public.current_is_full_access()
);
drop policy if exists overtime_records_read on public.overtime_records;
create policy overtime_records_read on public.overtime_records for select to authenticated using (
 employee_id=public.current_employee_id() or public.can_access_employee(employee_id,'attendance.overtime.approve')
 or public.current_is_full_access()
);

revoke insert,update,delete on public.attendance_periods,public.work_rosters,public.roster_days,public.attendance_corrections,public.overtime_records from authenticated;

create or replace function public.get_attendance_operations_catalog(p_month date default date_trunc('month',(now() at time zone 'Africa/Cairo'))::date)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_start date:=date_trunc('month',p_month)::date; v_end date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['attendance.record.read','attendance.roster.read','attendance.roster.manage'])) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 return jsonb_build_object(
  'month',v_start,
  'shifts',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'name',s.name,'startTime',s.start_time,'endTime',s.end_time,'crossesMidnight',s.crosses_midnight,'breakMinutes',s.break_minutes,'graceInMinutes',s.grace_in_minutes,'active',s.is_active) order by s.start_time) from public.shifts s),'[]'::jsonb),
  'rosters',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'code',r.code,'name',r.name,'periodStart',r.period_start,'periodEnd',r.period_end,'status',r.status,'departmentId',r.department_id,'teamId',r.team_id,'branchId',r.branch_id,'publishedAt',r.published_at,'days',coalesce((select count(*) from public.roster_days d where d.roster_id=r.id),0)) order by r.created_at desc) from public.work_rosters r where r.period_end>=v_start and r.period_start<=v_end),'[]'::jsonb),
  'corrections',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'employeeId',c.employee_id,'employeeName',e.full_name_ar,'employeeCode',e.employee_code,'workDate',c.work_date,'type',c.correction_type,'reason',c.reason,'status',c.status,'requestedCheckIn',c.requested_check_in,'requestedCheckOut',c.requested_check_out,'requestedStatus',c.requested_status,'createdAt',c.created_at) order by c.created_at desc) from public.attendance_corrections c join public.employees e on e.id=c.employee_id where c.work_date between v_start and v_end and (public.current_is_full_access() or c.employee_id=public.current_employee_id() or public.can_access_employee(c.employee_id,'attendance.correction.review'))),'[]'::jsonb),
  'overtime',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'employeeId',o.employee_id,'employeeName',e.full_name_ar,'employeeCode',e.employee_code,'workDate',o.work_date,'requestedMinutes',o.requested_minutes,'approvedMinutes',o.approved_minutes,'status',o.status,'reason',o.reason) order by o.work_date desc) from public.overtime_records o join public.employees e on e.id=o.employee_id where o.work_date between v_start and v_end and (public.current_is_full_access() or o.employee_id=public.current_employee_id() or public.can_access_employee(o.employee_id,'attendance.overtime.approve'))),'[]'::jsonb),
  'periods',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'periodMonth',p.period_month,'branchId',p.branch_id,'status',p.status,'closedAt',p.closed_at,'unlockedAt',p.unlocked_at,'unlockReason',p.unlock_reason)) from public.attendance_periods p where p.period_month=v_start),'[]'::jsonb),
  'summary',jsonb_build_object(
    'scheduled',(select count(*) from public.roster_days d where d.work_date between v_start and v_end and d.day_status='scheduled'),
    'present',(select count(*) from public.attendance_daily a where a.work_date between v_start and v_end and a.status in ('present','late')),
    'absent',(select count(*) from public.attendance_daily a where a.work_date between v_start and v_end and a.status='absent'),
    'pendingCorrections',(select count(*) from public.attendance_corrections c where c.work_date between v_start and v_end and c.status='pending'),
    'pendingOvertime',(select count(*) from public.overtime_records o where o.work_date between v_start and v_end and o.status='pending')
  ),
  'lastUpdatedAt',now()
 );
end $$;

create or replace function public.save_shift_admin(p_shift_id uuid,p_code text,p_name text,p_start time,p_end time,p_break_minutes integer default 0,p_grace_in integer default 0,p_grace_out integer default 0,p_active boolean default true)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if not(public.current_is_full_access() or public.has_permission('attendance.roster.manage')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(p_code))<2 or length(trim(p_name))<2 then raise exception 'INVALID_SHIFT'; end if;
 if p_shift_id is null then
  insert into public.shifts(code,name,start_time,end_time,crosses_midnight,break_minutes,grace_in_minutes,grace_out_minutes,is_active,created_by)
  values(upper(trim(p_code)),trim(p_name),p_start,p_end,p_end<=p_start,greatest(p_break_minutes,0),greatest(p_grace_in,0),greatest(p_grace_out,0),p_active,auth.uid()) returning id into v_id;
 else
  update public.shifts set code=upper(trim(p_code)),name=trim(p_name),start_time=p_start,end_time=p_end,crosses_midnight=p_end<=p_start,break_minutes=greatest(p_break_minutes,0),grace_in_minutes=greatest(p_grace_in,0),grace_out_minutes=greatest(p_grace_out,0),is_active=p_active,updated_at=now() where id=p_shift_id returning id into v_id;
 end if;
 perform public.log_audit_event('attendance.shift.saved','data','notice','shifts',v_id,'حفظ إعداد وردية',null,jsonb_build_object('code',p_code)); return v_id;
end $$;

create or replace function public.publish_roster_admin(p_name text,p_period_start date,p_period_end date,p_department_id uuid,p_team_id uuid,p_branch_id uuid,p_days jsonb,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_item jsonb; v_employee uuid; v_date date; v_shift uuid; v_status text; v_code text;
begin
 if not(public.current_is_full_access() or public.has_permission('attendance.roster.manage')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_period_end<p_period_start or jsonb_typeof(p_days)<>'array' then raise exception 'INVALID_ROSTER'; end if;
 v_code:='RST-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
 insert into public.work_rosters(code,name,period_start,period_end,department_id,team_id,branch_id,status,published_at,published_by,notes,created_by)
 values(v_code,trim(p_name),p_period_start,p_period_end,p_department_id,p_team_id,p_branch_id,'published',now(),public.current_employee_id(),p_notes,auth.uid()) returning id into v_id;
 for v_item in select * from jsonb_array_elements(p_days) loop
  v_employee:=(v_item->>'employeeId')::uuid; v_date:=(v_item->>'workDate')::date; v_shift:=nullif(v_item->>'shiftId','')::uuid; v_status:=coalesce(v_item->>'dayStatus','scheduled');
  if v_date<p_period_start or v_date>p_period_end or not public.can_access_employee(v_employee,'attendance.roster.manage') then raise exception 'ROSTER_SCOPE_OR_DATE_INVALID'; end if;
  insert into public.roster_days(roster_id,employee_id,work_date,shift_id,work_site_id,geofence_id,day_status,start_override,end_override,notes,created_by)
  values(v_id,v_employee,v_date,v_shift,nullif(v_item->>'workSiteId','')::uuid,nullif(v_item->>'geofenceId','')::uuid,v_status,nullif(v_item->>'startOverride','')::time,nullif(v_item->>'endOverride','')::time,v_item->>'notes',auth.uid());
 end loop;
 perform public.log_audit_event('attendance.roster.published','workflow','notice','work_rosters',v_id,'نشر جدول ورديات',null,jsonb_build_object('start',p_period_start,'end',p_period_end)); return v_id;
end $$;

create or replace function public.request_attendance_correction(p_work_date date,p_type text,p_reason text,p_check_in timestamptz default null,p_check_out timestamptz default null,p_status text default null,p_attachment_path text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_daily uuid;
begin
 if v_emp is null then raise exception 'NO_EMPLOYEE'; end if;
 if p_work_date>current_date or length(trim(p_reason))<5 then raise exception 'INVALID_CORRECTION'; end if;
 select id into v_daily from public.attendance_daily where employee_id=v_emp and work_date=p_work_date;
 insert into public.attendance_corrections(employee_id,attendance_daily_id,work_date,correction_type,requested_check_in,requested_check_out,requested_status,reason,attachment_path,created_by)
 values(v_emp,v_daily,p_work_date,p_type,p_check_in,p_check_out,p_status,trim(p_reason),p_attachment_path,auth.uid()) returning id into v_id;
 return v_id;
end $$;

create or replace function public.decide_attendance_correction(p_id uuid,p_decision text,p_note text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row public.attendance_corrections; v_daily uuid;
begin
 select * into strict v_row from public.attendance_corrections where id=p_id for update;
 if not(public.current_is_full_access() or public.can_access_employee(v_row.employee_id,'attendance.correction.review')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if v_row.status<>'pending' or p_decision not in ('approved','rejected') then raise exception 'INVALID_DECISION'; end if;
 if p_decision='rejected' and length(trim(coalesce(p_note,'')))<5 then raise exception 'REASON_REQUIRED'; end if;
 update public.attendance_corrections set status=p_decision,reviewed_by=public.current_employee_id(),reviewed_at=now(),review_note=p_note,updated_at=now() where id=p_id;
 if p_decision='approved' then
  insert into public.attendance_daily(employee_id,work_date,first_check_in,last_check_out,status,is_finalized,created_by)
  values(v_row.employee_id,v_row.work_date,v_row.requested_check_in,v_row.requested_check_out,coalesce(v_row.requested_status,'present'),false,auth.uid())
  on conflict(employee_id,work_date) do update set first_check_in=coalesce(v_row.requested_check_in,attendance_daily.first_check_in),last_check_out=coalesce(v_row.requested_check_out,attendance_daily.last_check_out),status=coalesce(v_row.requested_status,attendance_daily.status),updated_at=now();
 end if;
 perform public.log_audit_event('attendance.correction.'||p_decision,'workflow',case when p_decision='approved' then 'notice' else 'warning' end,'attendance_corrections',p_id,'قرار تصحيح حضور',p_note,jsonb_build_object('employeeId',v_row.employee_id,'workDate',v_row.work_date));
end $$;

create or replace function public.decide_overtime_record(p_id uuid,p_decision text,p_approved_minutes integer default null,p_note text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row public.overtime_records;
begin
 select * into strict v_row from public.overtime_records where id=p_id for update;
 if not(public.current_is_full_access() or public.can_access_employee(v_row.employee_id,'attendance.overtime.approve')) then raise exception 'FORBIDDEN'; end if;
 if v_row.status<>'pending' or p_decision not in ('approved','rejected') then raise exception 'INVALID_DECISION'; end if;
 update public.overtime_records set status=p_decision,approved_minutes=case when p_decision='approved' then least(coalesce(p_approved_minutes,v_row.requested_minutes),v_row.requested_minutes) else 0 end,approved_by=public.current_employee_id(),approved_at=now(),reason=coalesce(p_note,reason),updated_at=now() where id=p_id;
end $$;

create or replace function public.close_attendance_period(p_month date,p_legal_entity_id uuid default null,p_branch_id uuid default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_month date:=date_trunc('month',p_month)::date; v_id uuid; v_end date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;
begin
 if not(public.current_is_full_access() or public.has_permission('attendance.period.close')) then raise exception 'FORBIDDEN'; end if;
 if exists(select 1 from public.attendance_corrections c join public.employees e on e.id=c.employee_id where c.status='pending' and c.work_date between v_month and v_end and (p_branch_id is null or e.branch_id=p_branch_id)) then raise exception 'PENDING_CORRECTIONS'; end if;
 insert into public.attendance_periods(period_month,legal_entity_id,branch_id,status,closed_at,closed_by,snapshot,created_by)
 values(v_month,p_legal_entity_id,p_branch_id,'closed',now(),public.current_employee_id(),jsonb_build_object('dailyRows',(select count(*) from public.attendance_daily a join public.employees e on e.id=a.employee_id where a.work_date between v_month and v_end and (p_branch_id is null or e.branch_id=p_branch_id)),'closedAt',now()),auth.uid())
 on conflict(period_month,legal_entity_id,branch_id) do update set status='closed',closed_at=now(),closed_by=public.current_employee_id(),updated_at=now() returning id into v_id;
 update public.attendance_daily a set is_finalized=true,updated_at=now() from public.employees e where e.id=a.employee_id and a.work_date between v_month and v_end and (p_branch_id is null or e.branch_id=p_branch_id);
 return v_id;
end $$;

create or replace function public.unlock_attendance_period(p_period_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.attendance_periods; v_end date;
begin
 if not(public.current_is_full_access() or public.has_permission('attendance.period.unlock')) then raise exception 'FORBIDDEN'; end if;
 if length(trim(p_reason))<8 then raise exception 'REASON_REQUIRED'; end if;
 select * into strict v from public.attendance_periods where id=p_period_id for update; v_end:=(v.period_month+interval '1 month - 1 day')::date;
 update public.attendance_periods set status='unlocked',unlocked_at=now(),unlocked_by=public.current_employee_id(),unlock_reason=trim(p_reason),updated_at=now() where id=p_period_id;
 update public.attendance_daily a set is_finalized=false,updated_at=now() from public.employees e where e.id=a.employee_id and a.work_date between v.period_month and v_end and (v.branch_id is null or e.branch_id=v.branch_id);
 perform public.log_audit_event('attendance.period.unlocked','security','warning','attendance_periods',p_period_id,'إعادة فتح فترة حضور',p_reason,jsonb_build_object('period',v.period_month));
end $$;

revoke execute on function public.get_attendance_operations_catalog(date) from public; grant execute on function public.get_attendance_operations_catalog(date) to authenticated;
revoke execute on function public.save_shift_admin(uuid,text,text,time,time,integer,integer,integer,boolean) from public; grant execute on function public.save_shift_admin(uuid,text,text,time,time,integer,integer,integer,boolean) to authenticated;
revoke execute on function public.publish_roster_admin(text,date,date,uuid,uuid,uuid,jsonb,text) from public; grant execute on function public.publish_roster_admin(text,date,date,uuid,uuid,uuid,jsonb,text) to authenticated;
revoke execute on function public.request_attendance_correction(date,text,text,timestamptz,timestamptz,text,text) from public; grant execute on function public.request_attendance_correction(date,text,text,timestamptz,timestamptz,text,text) to authenticated;
revoke execute on function public.decide_attendance_correction(uuid,text,text) from public; grant execute on function public.decide_attendance_correction(uuid,text,text) to authenticated;
revoke execute on function public.decide_overtime_record(uuid,text,integer,text) from public; grant execute on function public.decide_overtime_record(uuid,text,integer,text) to authenticated;
revoke execute on function public.close_attendance_period(date,uuid,uuid) from public; grant execute on function public.close_attendance_period(date,uuid,uuid) to authenticated;
revoke execute on function public.unlock_attendance_period(uuid,text) from public; grant execute on function public.unlock_attendance_period(uuid,text) to authenticated;

commit;
