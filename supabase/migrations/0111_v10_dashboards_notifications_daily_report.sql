-- Align dashboards, action center, notifications and the executive daily report with V10.
begin;

create or replace function public.get_v10_executive_daily_report(p_date date default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_date date:=coalesce(p_date,(now() at time zone 'Africa/Cairo')::date); v_result jsonb;
begin
 if not (
   public.current_is_executive_secretary()
   or public.current_has_active_role(array['executive','executive-director'])
   or public.has_any_permission(array['reports.executive.read','reports.attendance.read','performance.kpi.report.read'])
 ) then raise exception 'EXECUTIVE_REPORT_FORBIDDEN' using errcode='42501'; end if;

 with active_people as (
   select e.id
   from public.employees e
   where e.is_active and not coalesce(e.is_deleted,false) and e.status='active'
     and not exists(
       select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
       where ur.user_id=e.user_id and r.slug in ('executive','executive-director')
         and (ur.effective_from is null or ur.effective_from<=now())
         and (ur.effective_to is null or ur.effective_to>now())
     )
 ), facts as (
   select p.id,d.status,d.first_check_in,d.last_check_out,d.late_minutes,
     not exists(select 1 from public.roster_days rd where rd.employee_id=p.id and rd.work_date=v_date and rd.day_status in ('rest','holiday','cancelled')) scheduled,
     exists(select 1 from public.leave_requests lr join public.requests rq on rq.id=lr.request_id where lr.employee_id=p.id and rq.status='approved' and v_date between lr.start_date and lr.end_date) on_leave,
     (select wa.assignment_type from public.work_assignment_participants wp join public.work_assignments wa on wa.id=wp.assignment_id where wp.employee_id=p.id and wa.status in ('APPROVED','IN_PROGRESS','REPORT_PENDING','REPORT_SUBMITTED') and v_date between (wa.start_at at time zone 'Africa/Cairo')::date and (wa.end_at at time zone 'Africa/Cairo')::date order by wa.start_at desc limit 1) assignment_type
   from active_people p left join public.attendance_daily d on d.employee_id=p.id and d.work_date=v_date
 ), attendance_summary as (
   select count(*) total_active,
     count(*) filter(where scheduled and not on_leave and assignment_type is null) required_today,
     count(*) filter(where first_check_in is not null or status in ('present','late','partial')) present,
     count(*) filter(where status='late' or coalesce(late_minutes,0)>0) late,
     count(*) filter(where status='absent') absent,
     count(*) filter(where scheduled and not on_leave and assignment_type is null and first_check_in is null and coalesce(status,'')<>'absent') not_yet,
     count(*) filter(where last_check_out is not null) checked_out,
     count(*) filter(where scheduled and first_check_in is not null and last_check_out is null) missing_checkout,
     count(*) filter(where on_leave) approved_leave,
     count(*) filter(where assignment_type='MISSION') missions,
     count(*) filter(where assignment_type='CONVOY') convoys,
     count(*) filter(where assignment_type='FUNDRAISING') fundraising
   from facts
 ), kpi_summary as (
   select
    count(*) filter(where e.current_stage='self') at_employee,
    count(*) filter(where e.current_stage in ('manager_review','manager_final')) at_manager,
    count(*) filter(where e.current_stage='hr_review') at_hr,
    count(*) filter(where e.current_stage in ('finalized','closed','archived')) ready,
    count(*) filter(where e.workflow_status='OVERDUE') overdue
   from public.kpi_evaluations e join public.kpi_cycles c on c.id=e.cycle_id
   where c.period_month=date_trunc('month',v_date)::date
 )
 select jsonb_build_object(
  'date',v_date,
  'employees',jsonb_build_object('active',a.total_active,'requiredToday',a.required_today),
  'attendance',jsonb_build_object('present',a.present,'late',a.late,'absent',a.absent,'notYet',a.not_yet,'checkedOut',a.checked_out,'missingCheckout',a.missing_checkout),
  'workStatus',jsonb_build_object('approvedLeave',a.approved_leave,'missions',a.missions,'convoys',a.convoys,'fundraising',a.fundraising),
  'requests',jsonb_build_object(
    'pendingLeave',(select count(*) from public.requests where request_type='leave' and status='pending'),
    'pendingMission',(select count(*) from public.requests where request_type in ('mission','convoy') and status='pending')
  ),
  'kpi',jsonb_build_object('atEmployee',k.at_employee,'atManager',k.at_manager,'atHr',k.at_hr,'ready',k.ready,'overdue',k.overdue),
  'cases',jsonb_build_object('new',(select count(*) from public.dispute_cases where status in ('submitted','needs_more_information')),'open',(select count(*) from public.dispute_cases where status not in ('closed','rejected','cancelled_by_employee'))),
  'followUp',jsonb_build_object(
    'decisions',(select count(*) from public.administrative_decisions where status in ('draft','in_review','approved')),
    'missingReports',(select count(*) from public.work_assignments where status='REPORT_PENDING'),
    'activeLocationRequests',(select count(*) from public.live_location_requests where status in ('pending','accepted','active') and (expires_at is null or expires_at>now())),
    'unansweredLocationRequests',(select count(*) from public.live_location_requests where status='pending' and (expires_at is null or expires_at>now()))
  ),
  'sources',jsonb_build_object(
    'employees','employees + user_roles','attendance','attendance_daily + roster_days',
    'workStatus','leave_requests + work_assignments','requests','requests',
    'kpi','kpi_evaluations + kpi_cycles','cases','dispute_cases',
    'followUp','administrative_decisions + work_assignments + live_location_requests'
  ),
  'generatedAt',now()
 ) into v_result from attendance_summary a cross join kpi_summary k;
 return v_result;
end $$;

revoke all on function public.get_v10_executive_daily_report(date) from public,anon;
grant execute on function public.get_v10_executive_daily_report(date) to authenticated;

create or replace function public.get_manager_dashboard()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_me uuid:=public.current_employee_id();
begin
 return jsonb_build_object(
  'teamMembers',(select count(*) from public.manager_relations mr join public.employees e on e.id=mr.employee_id where mr.manager_employee_id=v_me and mr.relation_type='primary' and mr.effective_from<=current_date and (mr.effective_to is null or mr.effective_to>=current_date) and e.is_active and not coalesce(e.is_deleted,false)),
  'pendingRequests',(select count(*) from public.requests r where r.status='pending' and r.employee_id<>v_me and public.can_access_employee(r.employee_id,'requests.request.approve')),
  'pendingKpi',(select count(*) from public.kpi_evaluations k where k.current_stage in ('manager_review','manager_final') and public.kpi_is_direct_manager(k.employee_id)),
  'lateToday',(select count(*) from public.attendance_daily d where d.work_date=(now() at time zone 'Africa/Cairo')::date and (d.status='late' or d.late_minutes>0) and exists(select 1 from public.manager_relations mr where mr.manager_employee_id=v_me and mr.employee_id=d.employee_id and mr.relation_type='primary' and mr.effective_from<=current_date and (mr.effective_to is null or mr.effective_to>=current_date))),
  'lastUpdatedAt',now()
 );
end $$;

create or replace function public.get_executive_dashboard()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_daily jsonb;
begin
 v_daily:=public.get_v10_executive_daily_report(null);
 return jsonb_build_object(
  'urgentActions',coalesce((v_daily#>>'{followUp,unansweredLocationRequests}')::integer,0)+coalesce((v_daily#>>'{kpi,overdue}')::integer,0),
  'pendingApprovals',coalesce((v_daily#>>'{requests,pendingLeave}')::integer,0)+coalesce((v_daily#>>'{requests,pendingMission}')::integer,0),
  'pendingFinalKpi',coalesce((v_daily#>>'{kpi,ready}')::integer,0),
  'publishedDecisions',(select count(*) from public.administrative_decisions where status='published'),
  'openCases',coalesce((v_daily#>>'{cases,open}')::integer,0),
  'activeLocationRequests',coalesce((v_daily#>>'{followUp,activeLocationRequests}')::integer,0),
  'dailyReport',v_daily,
  'lastUpdatedAt',now()
 );
end $$;

create or replace function public.get_mobile_executive_brief(p_period text default 'morning')
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_today date:=(now() at time zone 'Africa/Cairo')::date; v_daily jsonb; v_previous jsonb;
begin
 if p_period not in ('morning','evening') then raise exception 'INVALID_BRIEF_PERIOD' using errcode='22023'; end if;
 v_daily:=public.get_v10_executive_daily_report(v_today);
 v_previous:=public.get_v10_executive_daily_report(v_today-1);
 return jsonb_build_object(
  'period',p_period,'briefDate',v_today,
  'attendance',jsonb_build_object(
    'presentToday',coalesce((v_daily#>>'{attendance,present}')::integer,0),
    'presentYesterday',coalesce((v_previous#>>'{attendance,present}')::integer,0),
    'lateToday',coalesce((v_daily#>>'{attendance,late}')::integer,0),
    'lateYesterday',coalesce((v_previous#>>'{attendance,late}')::integer,0),
    'absentToday',coalesce((v_daily#>>'{attendance,absent}')::integer,0),
    'onLeaveToday',coalesce((v_daily#>>'{workStatus,approvedLeave}')::integer,0),
    'weekAverageLate',coalesce((select round(avg(x.n),1) from (select count(*)::numeric n from public.attendance_daily where work_date between v_today-7 and v_today-1 and (status='late' or late_minutes>0) group by work_date)x),0)
  ),
  'decisions',jsonb_build_object(
    'urgentActions',coalesce((v_daily#>>'{followUp,unansweredLocationRequests}')::integer,0)+coalesce((v_daily#>>'{kpi,overdue}')::integer,0),
    'pendingApprovals',coalesce((v_daily#>>'{requests,pendingLeave}')::integer,0)+coalesce((v_daily#>>'{requests,pendingMission}')::integer,0),
    'pendingFinalKpi',coalesce((v_daily#>>'{kpi,ready}')::integer,0),
    'decisionsInReview',coalesce((v_daily#>>'{followUp,decisions}')::integer,0),
    'publishedToday',(select count(*) from public.administrative_decisions where status='published' and published_at>=v_today::timestamptz),
    'reportsReadyToday',coalesce((v_daily#>>'{kpi,ready}')::integer,0)
  ),
  'risk',jsonb_build_object(
    'criticalRisks',(select count(*) from public.risks where status in ('open','mitigating') and severity='critical'),
    'highRisks',(select count(*) from public.risks where status in ('open','mitigating') and severity='high'),
    'activeIncidents',(select count(*) from public.incidents where status in ('open','investigating')),
    'criticalIncidents',(select count(*) from public.incidents where status in ('open','investigating') and severity='critical')
  ),
  'highlights',jsonb_build_array(
    jsonb_build_object('kind','attendance','title','لم يسجلوا بعد','value',coalesce((v_daily#>>'{attendance,notYet}')::integer,0),'severity','high','detail','من جميع الموظفين المطلوب حضورهم اليوم'),
    jsonb_build_object('kind','attendance','title','لم يسجلوا الانصراف','value',coalesce((v_daily#>>'{attendance,missingCheckout}')::integer,0),'severity','high','detail','حالات تحتاج متابعة اكتمال اليوم'),
    jsonb_build_object('kind','kpi','title','تقارير KPI جاهزة','value',coalesce((v_daily#>>'{kpi,ready}')::integer,0),'severity','normal','detail','تقارير اعتمدها المدير المباشر'),
    jsonb_build_object('kind','case','title','قضايا جديدة','value',coalesce((v_daily#>>'{cases,new}')::integer,0),'severity','high','detail','قضايا تنتظر بدء الإجراء'),
    jsonb_build_object('kind','location','title','طلبات موقع بلا استجابة','value',coalesce((v_daily#>>'{followUp,unansweredLocationRequests}')::integer,0),'severity','critical','detail','طلبات نشطة لم يفتحها المستلم بعد')
  ),
  'dailyReport',v_daily,'generatedAt',now(),'sourceLabel','مصادر V10 التشغيلية المباشرة'
 );
end $$;

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
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'subtitle',subtitle,'priority',priority,'status',status,'dueAt',due_at,'actionUrl',action_url,'sourceUpdatedAt',source_updated_at) order by case priority when 'urgent' then 1 when 'high' then 2 else 3 end,due_at nulls last),'[]'::jsonb)
 from (select * from actions order by source_updated_at desc limit greatest(1,least(coalesce(p_limit,100),500))) limited;
$$;

create or replace function public.generate_kpi_cycle_notifications(p_at timestamptz default now())
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles; v_eval record; v_recipient uuid; v_day integer:=(p_at at time zone 'Africa/Cairo')::date-(date_trunc('month',p_at at time zone 'Africa/Cairo'))::date+1; v_count integer:=0; v_event text; v_title text; v_body text;
begin
 for v_cycle in select * from public.kpi_cycles where status in ('open','locked') and period_month=date_trunc('month',p_at at time zone 'Africa/Cairo')::date loop
  if v_day>=20 then
   for v_eval in select e.id,e.employee_id,(select mr.manager_employee_id from public.manager_relations mr where mr.employee_id=e.employee_id and mr.relation_type='primary' and mr.effective_from<=current_date and (mr.effective_to is null or mr.effective_to>=current_date) limit 1) manager_id from public.kpi_evaluations e where e.cycle_id=v_cycle.id loop
    if public.enqueue_kpi_notification(v_cycle.id,v_eval.id,'OPENED_EMPLOYEE',v_eval.employee_id,'بدأت دورة تقييم الأداء','أكمل تقييمك الذاتي للبنود السبعة قبل نهاية الدورة.','normal') is not null then v_count:=v_count+1; end if;
    if v_eval.manager_id is not null and public.enqueue_kpi_notification(v_cycle.id,v_eval.id,'OPENED_MANAGER',v_eval.manager_id,'بدأت دورة تقييم فريقك','ستصلك تقييمات أعضاء فريقك للمراجعة ثم الاعتماد النهائي.','normal') is not null then v_count:=v_count+1; end if;
   end loop;
  end if;
  if p_at>public.kpi_effective_deadline(v_cycle) then v_event:='OVERDUE';v_title:='تقييمات أداء متأخرة';v_body:='انتهى الموعد وما زالت تقييمات غير مكتملة.';
  elsif v_day>=25 then v_event:='REMINDER_25';v_title:='اليوم آخر موعد لتقييم الأداء';v_body:='أكمل الإجراء المطلوب قبل إغلاق الدورة.';
  elsif v_day>=24 then v_event:='REMINDER_24';v_title:='غدًا آخر موعد لتقييم الأداء';v_body:='يوجد تقييم لم يكتمل بعد.';
  elsif v_day>=22 then v_event:='REMINDER_22';v_title:='تذكير بتقييم الأداء';v_body:='أكمل المرحلة المسندة إليك قبل الموعد.';
  else continue; end if;
  if v_event='OVERDUE' then
   for v_recipient in select distinct p.employee_id from public.user_roles ur join public.roles r on r.id=ur.role_id join public.profiles p on p.id=ur.user_id where r.slug='executive-secretary' and p.employee_id is not null and ur.effective_from<=p_at and (ur.effective_to is null or ur.effective_to>p_at) loop
    if public.enqueue_kpi_notification(v_cycle.id,null,v_event,v_recipient,v_title,v_body,'urgent') is not null then v_count:=v_count+1; end if;
   end loop;
  else
   for v_eval in select e.id,e.employee_id,e.current_stage,(select mr.manager_employee_id from public.manager_relations mr where mr.employee_id=e.employee_id and mr.relation_type='primary' and mr.effective_from<=current_date and (mr.effective_to is null or mr.effective_to>=current_date) limit 1) manager_id from public.kpi_evaluations e where e.cycle_id=v_cycle.id and e.current_stage not in ('finalized','closed','archived') loop
    if v_eval.current_stage='hr_review' then
     for v_recipient in select distinct p.employee_id from public.user_roles ur join public.roles r on r.id=ur.role_id join public.profiles p on p.id=ur.user_id where r.slug in ('hr-manager','hr-specialist') and p.employee_id is not null and ur.effective_from<=p_at and (ur.effective_to is null or ur.effective_to>p_at) loop
      if public.enqueue_kpi_notification(v_cycle.id,v_eval.id,v_event,v_recipient,v_title,v_body,case when v_event='REMINDER_25' then 'urgent' else 'high' end) is not null then v_count:=v_count+1; end if;
     end loop;
    else
     v_recipient:=case when v_eval.current_stage='self' then v_eval.employee_id when v_eval.current_stage in ('manager_review','manager_final') then v_eval.manager_id else null end;
     if v_recipient is not null and public.enqueue_kpi_notification(v_cycle.id,v_eval.id,v_event,v_recipient,v_title,v_body,case when v_event='REMINDER_25' then 'urgent' else 'high' end) is not null then v_count:=v_count+1; end if;
    end if;
   end loop;
  end if;
 end loop;
 return v_count;
end $$;

revoke all on function public.get_manager_dashboard() from public,anon;
revoke all on function public.get_executive_dashboard() from public,anon;
revoke all on function public.get_mobile_executive_brief(text) from public,anon;
revoke all on function public.get_universal_action_center(integer) from public,anon;
grant execute on function public.get_manager_dashboard() to authenticated;
grant execute on function public.get_executive_dashboard() to authenticated;
grant execute on function public.get_mobile_executive_brief(text) to authenticated;
grant execute on function public.get_universal_action_center(integer) to authenticated;

commit;
