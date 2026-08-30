-- ============================================================================
-- 0476: تبسيط مسار KPI — سياسة «ذاتي ← مدير ← اعتراف» (V24)
-- ============================================================================
-- القرار السياسي: إلغاء التعقيد الهيكلي في تقييم الأداء:
--   ✗ لا مرحلة hr_review كبوابة عرقلة — HR بيانات استثنائية لا شرط انطلاق
--   ✗ لا manager_final منفصلة — المدير يقيّم ويعتمد في خطوة واحدة
--   ✗ لا مسار متوازٍ (parallel/secretary/executive) في الدورات الجديدة
--   ✓ الموظف يقيّم نفسه (مرجع مقارنة يراه المدير)
--   ✓ المدير المباشر يقدّم الدرجات والاعتماد النهائي معاً
--   ✓ بنود HR (الحضور/الصلاة/الحلقة) تُحتسب آلياً، وأي بند بلا إدخال
--     يأخذ الدرجة الكاملة كقيمة افتراضية معلنة (الاستثناء بالخصم لا بالإثبات)
--   ✓ مدير مفقود؟ يُحل الموافِق آلياً: مدير مباشر ← HR ← السكرتير التنفيذي
--   ✓ بعد الاعتماد: اعتراف الموظف أو اعتراضه موثّقاً
--
-- التوافق الرجعي:
--   * الدورات الجارية تُهجَّر: hr_review وmanager_final تنضغط إلى
--     manager_review ليعيد المدير التقديم مرة واحدة.
--   * دورات المسار المتوازي القائمة تبقى كما هي؛ أي محاولة تحريكها ترجع
--     خطأ KPI_FLOW_SIMPLIFIED ويُعاد فتحها يدوياً بالتسوية (ميزة اختيارية نادراً ما فُعّلت).
--   * create_kpi_cycle_admin يحافظ على توقيعه (الويب يرسل p_use_parallel_flow)
--     لكن العلم يُتجاهل قسراً = false.
-- ============================================================================

begin;

-- ─── 1) تهجير الدورات الجارية غير المقفلة ──────────────────────────────────
update public.kpi_evaluations
   set current_stage = 'manager_review',
       stage = 'manager_review',
       workflow_status = case when workflow_status = 'DRAFT' then workflow_status
                              else 'SUBMITTED_TO_DIRECT_MANAGER' end,
       updated_at = now()
 where locked = false
   and current_stage in ('hr_review','manager_final');

comment on table public.kpi_evaluations is
 '0470: المسار القانوني self → manager_review → finalized (+اعتراف الموظف عبر workflow_status). المراحل التاريخية (hr_review/manager_final/parallel_*) صالحة للقراءة فقط من دورات مغلقة سابقة.';

-- ─── 2) حَلُّ الموافِق عند غياب المدير المباشر ─────────────────────────────
create or replace function public.kpi_resolve_approver_for_employee(p_employee_id uuid)
returns uuid
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_mgr uuid;
begin
  -- مدير مباشر نشط
  select mr.manager_employee_id into v_mgr
    from public.manager_relations mr
   where mr.employee_id = p_employee_id
     and mr.relation_type = 'primary'
     and mr.effective_from <= current_date
     and (mr.effective_to is null or mr.effective_to >= current_date)
   order by mr.effective_from desc limit 1;
  if v_mgr is not null then return v_mgr; end if;

  -- بديل 1: أول موظف فعّال بدور hr-manager
  select e.id into v_mgr
    from public.employees e
    join public.profiles pr on pr.employee_id = e.id and pr.status = 'active'
    join public.user_roles ur on ur.user_id = pr.id
    join public.roles r on r.id = ur.role_id and r.slug = 'hr-manager'
   where e.is_active and e.status = 'active'
     and (ur.effective_from is null or ur.effective_from <= now())
     and (ur.effective_to is null or ur.effective_to > now())
   order by e.hire_date limit 1;
  if v_mgr is not null then return v_mgr; end if;

  -- بديل 2: أول موظف فعّال بدور executive-secretary
  select e.id into v_mgr
    from public.employees e
    join public.profiles pr on pr.employee_id = e.id and pr.status = 'active'
    join public.user_roles ur on ur.user_id = pr.id
    join public.roles r on r.id = ur.role_id and r.slug = 'executive-secretary'
   where e.is_active and e.status = 'active'
     and (ur.effective_from is null or ur.effective_from <= now())
     and (ur.effective_to is null or ur.effective_to > now())
   order by e.hire_date limit 1;
  return v_mgr;
end $$;

comment on function public.kpi_resolve_approver_for_employee(uuid) is
 '0470: مَن يعتمد تقييم الموظف؟ مدير مباشر نشط، وإلا HR، وإلا السكرتير التنفيذي — لا موظف عالق.';

-- ─── 3) هل المستدعي مخوّل باعتماد هذا التقييم؟ ─────────────────────────────
create or replace function public.kpi_can_approve(p_evaluation public.kpi_evaluations)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  return public.current_is_full_access()
      or public.current_employee_id() = public.kpi_resolve_approver_for_employee(p_evaluation.employee_id);
end;
$$;

-- ─── 4) إنشاء الدورة: تجاهل علم المسار المتواز قسراً ───────────────────────
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
 if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select id into strict v_template from public.kpi_templates where official_code='OFFICIAL_KPI_100' and is_active;
 if p_template_id is distinct from v_template then raise exception 'ONLY_OFFICIAL_KPI_TEMPLATE_IS_ALLOWED'; end if;
 select id into strict v_policy from public.kpi_policy_versions where is_active;
 v_open:=((v_month+19)::timestamp at time zone 'Africa/Cairo');
 v_deadline:=(((v_month+25)::timestamp at time zone 'Africa/Cairo')-interval '1 second');
 if coalesce(p_open_now,false) and now() between v_open and v_deadline then v_status:='open'; end if;
 -- 0470: p_use_parallel_flow مقبول توافقاً لكنه مُهمَل — المسار الوحيد هو V24
 insert into public.kpi_cycles(period_month,status,template_id,scheduled_open_at,deadline_at,self_due_at,manager_due_at,secretary_due_at,executive_due_at,opened_at,opened_by,policy_version_id,use_parallel_flow,created_by)
 values(v_month,v_status,v_template,v_open,v_deadline,v_deadline,v_deadline,v_deadline,v_deadline,case when v_status='open' then now() end,case when v_status='open' then public.current_employee_id() end,v_policy,false,auth.uid())
 on conflict(period_month) do update set
  template_id=excluded.template_id,scheduled_open_at=excluded.scheduled_open_at,deadline_at=excluded.deadline_at,
  self_due_at=excluded.self_due_at,manager_due_at=excluded.manager_due_at,
  secretary_due_at=excluded.secretary_due_at,executive_due_at=excluded.executive_due_at,
  policy_version_id=coalesce(kpi_cycles.policy_version_id,excluded.policy_version_id),
  use_parallel_flow=false,updated_at=now()
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
 perform public.log_audit_event('kpi.cycle.created','workflow','notice','kpi_cycles',v_id,'إنشاء دورة KPI (مسار مبسّط 0470)',null,jsonb_build_object('month',v_month,'status',v_status));
 return v_id;
end $$;

-- ─── 5) advance_kpi_stage — المسار القانوني الوحيد ─────────────────────────
create or replace function public.advance_kpi_stage(
 p_evaluation_id uuid, p_action text, p_scores jsonb default null, p_note text default null
)
returns public.kpi_evaluations
language plpgsql security definer set search_path = public, pg_temp as $$
declare
 v_eval public.kpi_evaluations; v_cycle public.kpi_cycles;
 v_row jsonb; v_criterion public.kpi_criteria; v_score numeric;
 v_required int; v_received int; v_errors text[]; v_total numeric; v_rating text;
 v_att record;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id for update;
 if v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle)
   then raise exception 'KPI_CYCLE_CLOSED'; end if;
 if length(coalesce(p_note,''))>5000 then raise exception 'NOTE_TOO_LONG'; end if;

 -- رفض صريح لأفعال المسارات القديمة
 if p_action not in ('self','manager_review') then
   raise exception 'KPI_FLOW_SIMPLIFIED: % لم يعد مساراً صالحاً منذ 0470 (self / manager_review فقط)', p_action
     using errcode='22023';
 end if;
 if v_eval.current_stage<>p_action then
   raise exception 'STAGE_OUT_OF_ORDER expected %, found %', p_action, v_eval.current_stage;
 end if;

 -- ══════════ ① التقييم الذاتي ══════════
 if p_action='self' then
  if v_eval.workflow_status='DRAFT' or v_eval.employee_id<>public.current_employee_id()
     or not public.has_permission('performance.kpi.self_assess')
   then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if p_scores is null or jsonb_typeof(p_scores)<>'array' then raise exception 'SELF_SCORES_REQUIRED'; end if;
  select count(*) into v_required from public.kpi_criteria where template_id=v_eval.template_id;
  select count(*) into v_received from jsonb_array_elements(p_scores);
  if v_received<>v_required then raise exception 'ALL_SELF_CRITERIA_REQUIRED'; end if;
  for v_row in select * from jsonb_array_elements(p_scores) loop
   select * into v_criterion from public.kpi_criteria
    where id=(v_row->>'criterion_id')::uuid and template_id=v_eval.template_id;
   if v_criterion.id is null then raise exception 'INVALID_SELF_CRITERION'; end if;
   v_score:=(v_row->>'score')::numeric;
   if v_score<0 or v_score>v_criterion.max_score then raise exception 'SCORE_OUT_OF_RANGE'; end if;
   insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
   values(v_eval.id,v_criterion.id,v_score,'self',nullif(trim(v_row->>'note'),''),auth.uid())
   on conflict(evaluation_id,criterion_id,reviewer_stage) do update
     set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
  end loop;
  update public.kpi_evaluations set
   stage='manager_review',current_stage='manager_review',
   workflow_status='SUBMITTED_TO_DIRECT_MANAGER',
   version=version+1,updated_at=now()
  where id=v_eval.id returning * into v_eval;
  perform public.log_audit_event('kpi.stage_advanced','workflow','notice','kpi_evaluations',v_eval.id,
   'إرسال التقييم الذاتي إلى المدير (0470)',null,jsonb_build_object('to','manager_review'));
  return v_eval;
 end if;

 -- ══════════ ② تقييم المدير واعتماده النهائي في خطوة واحدة ══════════
 if not public.kpi_can_approve(v_eval) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_note,'')))<3 then raise exception 'MANAGER_COMMENT_REQUIRED'; end if;
 if p_scores is null or jsonb_typeof(p_scores)<>'array' then raise exception 'MANAGER_SCORES_REQUIRED'; end if;

 select count(*) into v_required from public.kpi_criteria
  where template_id=v_eval.template_id and evaluator_stage='manager';
 select count(*) into v_received from jsonb_array_elements(p_scores);
 if v_received<>v_required then raise exception 'ALL_MANAGER_CRITERIA_REQUIRED'; end if;
 for v_row in select * from jsonb_array_elements(p_scores) loop
  select * into v_criterion from public.kpi_criteria
   where id=(v_row->>'criterion_id')::uuid and template_id=v_eval.template_id and evaluator_stage='manager';
  if v_criterion.id is null then raise exception 'INVALID_MANAGER_CRITERION'; end if;
  v_score:=(v_row->>'score')::numeric;
  if v_score<0 or v_score>v_criterion.max_score then raise exception 'SCORE_OUT_OF_RANGE'; end if;
  insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
  values(v_eval.id,v_criterion.id,v_score,'manager',nullif(trim(v_row->>'note'),''),auth.uid())
  on conflict(evaluation_id,criterion_id,reviewer_stage) do update
    set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
 end loop;

 -- بنود HR: الحضور يُحتسب موضعياً لهذا التقييم، وما بقي بلا إدخال يأخذ الدرجة الكاملة افتراضياً (الاستثناء بالخصم)
 for v_att in
  select k.id criterion_id,k.attendance_metric,k.max_score,
   count(a.*) filter(where a.status not in ('holiday','weekend')) scheduled,
   count(a.*) filter(where a.status in ('present','late')) present,
   count(a.*) filter(where a.status='present') punctual,
   count(a.*) filter(where a.status in ('present','late','on_leave','holiday','weekend')) completed
  from public.kpi_criteria k
  left join public.attendance_daily a on a.employee_id=v_eval.employee_id
    and date_trunc('month',a.work_date)=v_cycle.period_month
  where k.template_id=v_eval.template_id and k.source_type='attendance'
  group by k.id,k.attendance_metric,k.max_score
 loop
  v_score:=case v_att.attendance_metric
    when 'punctuality_rate' then case when v_att.scheduled=0 then v_att.max_score else round(v_att.punctual::numeric/v_att.scheduled*v_att.max_score,2) end
    when 'completion_rate'  then case when v_att.scheduled=0 then v_att.max_score else round(v_att.completed::numeric/v_att.scheduled*v_att.max_score,2) end
    else case when v_att.scheduled=0 then v_att.max_score else round(v_att.present::numeric/v_att.scheduled*v_att.max_score,2) end end;
  insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
  values(v_eval.id,v_att.criterion_id,greatest(0,least(v_score,v_att.max_score)),'hr','محسوب آلياً من الحضور (0470)',auth.uid())
  on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now();
 end loop;
 update public.kpi_evaluations set manager_comment=nullif(trim(p_note),''),updated_at=now() where id=v_eval.id;
 insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
 select v_eval.id, c.id, c.max_score, 'hr', 'قيمة افتراضية (0470): لا استثناء مسجلاً', auth.uid()
   from public.kpi_criteria c
  where c.template_id=v_eval.template_id and c.evaluator_stage='hr'
    and not exists(select 1 from public.kpi_scores s
                    where s.evaluation_id=v_eval.id and s.criterion_id=c.id and s.reviewer_stage='hr')
on conflict (evaluation_id,criterion_id,reviewer_stage) do nothing;

 v_errors:=public.get_kpi_validation_errors(v_eval.id);
 if cardinality(v_errors)>0 then raise exception 'KPI_VALIDATION_FAILED: %',array_to_string(v_errors,' | '); end if;
 v_total:=public.kpi_total_score(v_eval.id);
 if v_total<0 or v_total>100 then raise exception 'FINAL_SCORE_OUT_OF_RANGE'; end if;
 v_rating:=public.kpi_rating_for_score(v_cycle.policy_version_id,v_total);

 update public.kpi_evaluations set
  stage='finalized',current_stage='finalized',
  workflow_status='EMPLOYEE_ACKNOWLEDGEMENT_PENDING',
  manager_approved_at=now(),manager_approved_by=public.current_employee_id(),
  final_score=v_total,final_rating=v_rating,
  final_breakdown=(select jsonb_object_agg(c.code,public.kpi_effective_score(v_eval.id,c.id))
                     from public.kpi_criteria c where c.template_id=v_eval.template_id),
  rating_policy_snapshot=(select rating_bands from public.kpi_policy_versions where id=v_cycle.policy_version_id),
  locked=true,version=version+1,updated_at=now()
 where id=v_eval.id returning * into v_eval;

 perform public.log_audit_event('kpi.stage_advanced','workflow','notice','kpi_evaluations',v_eval.id,
  'اعتماد المدير الشامل (0470)',p_note,
  jsonb_build_object('finalScore',v_total,'finalRating',v_rating));
 perform public.log_audit_event('kpi.monthly_report.included','workflow','info','kpi_evaluations',v_eval.id,
  'إدراج التقييم في التقرير الشهري',null,jsonb_build_object('cycleId',v_eval.cycle_id));
 return v_eval;
end $$;

-- ─── 6) إقرار/اعتراض الموظف على النتيجة النهائية ──────────────────────────
-- التوقيع متوافق مع واجهة الموبايل (acknowledge_kpi_evaluation):
--   p_note = تعليق حر عند الإقرار، p_appeal_reason = سبب الاعتراض الموثق.
create or replace function public.acknowledge_kpi_evaluation(
 p_evaluation_id uuid, p_note text default null, p_appeal_reason text default null
)
returns public.kpi_evaluations
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_eval public.kpi_evaluations;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if v_eval.employee_id<>public.current_employee_id() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if not v_eval.locked or v_eval.current_stage<>'finalized' then raise exception 'KPI_NOT_FINALIZED'; end if;
 if length(coalesce(p_note,''))>2000 or length(coalesce(p_appeal_reason,''))>2000
  then raise exception 'NOTE_TOO_LONG'; end if;

 if coalesce(trim(p_appeal_reason),'')<>'' then
  -- الاعتراض لا يغيّر الحالة المقفلة؛ يوثَّق ويُبلَّغ للموافق لحسمه
  perform public.log_audit_event('kpi.result.disputed','workflow','warning','kpi_evaluations',v_eval.id,
   'اعتراض الموظف على نتيجة التقييم',trim(p_appeal_reason),
   jsonb_build_object('finalScore',v_eval.final_score,'approver',public.kpi_resolve_approver_for_employee(v_eval.employee_id)));
 else
  update public.kpi_evaluations set workflow_status='EMPLOYEE_ACKNOWLEDGED',updated_at=now()
   where id=v_eval.id returning * into v_eval;
  perform public.log_audit_event('kpi.result.acknowledged','workflow','notice','kpi_evaluations',v_eval.id,
   'إقرار الموظف بنتيجة تقييمه',nullif(trim(p_note),''),null);
 end if;
 return v_eval;
end $$;

-- ─── 6.5) استثناءات HR (صلاة/حلقة): في أي وقت قبل القفل بلا قيد مرحلة ──────
create or replace function public.save_kpi_compliance_metric(
 p_evaluation_id uuid,p_metric text,p_required integer,p_actual integer,p_exempt integer default 0,p_cancelled integer default 0,p_note text default null
)
returns numeric language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_eligible integer; v_score numeric; v_criterion uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 -- 0470: لا بوابة مراحل — يكفي أن يكون التقييم غير مقفل والمُدخل من مراجعي HR
 if v_eval.locked or not public.current_is_hr_reviewer() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_metric not in ('PRAYER','HALAQA') or least(p_required,p_actual,p_exempt,p_cancelled)<0 then raise exception 'INVALID_COMPLIANCE_INPUT'; end if;
 v_eligible:=greatest(p_required-p_exempt-p_cancelled,0);
 if p_actual>v_eligible then raise exception 'ACTUAL_EXCEEDS_REQUIRED'; end if;
 v_score:=case when v_eligible=0 then 5 else round(p_actual::numeric/v_eligible*5,2) end;
 insert into public.kpi_compliance_records(evaluation_id,metric,required_count,actual_count,exempt_count,cancelled_count,calculated_score,note,approved_at,approved_by,created_by)
 values(p_evaluation_id,p_metric,p_required,p_actual,p_exempt,p_cancelled,v_score,p_note,now(),public.current_employee_id(),auth.uid())
 on conflict(evaluation_id,metric) do update set required_count=excluded.required_count,actual_count=excluded.actual_count,exempt_count=excluded.exempt_count,cancelled_count=excluded.cancelled_count,calculated_score=excluded.calculated_score,note=excluded.note,approved_at=now(),approved_by=public.current_employee_id(),updated_at=now();
 select c.id into strict v_criterion from public.kpi_criteria c where c.template_id=v_eval.template_id and c.code=p_metric;
 insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
 values(p_evaluation_id,v_criterion,v_score,'hr',p_note,auth.uid())
 on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
 perform public.log_audit_event('kpi.compliance.calculated','workflow','info','kpi_evaluations',p_evaluation_id,'احتساب معيار HR',null,jsonb_build_object('metric',p_metric,'score',v_score));
 return v_score;
end $$;

revoke all on function public.save_kpi_compliance_metric(uuid,text,integer,integer,integer,integer,text) from public, anon;
grant  execute on function public.save_kpi_compliance_metric(uuid,text,integer,integer,integer,integer,text) to authenticated;

-- ─── 6.6) مدقق الصلاحية يتواءم مع العقد الجديد ────────────────────────────
-- يُسقطان فحصا بوابتين أُلغيتا سياسياً في 0470:
--   ✗ اشتراط وجود kpi_attendance_snapshots بلا معلّقات
--   ✗ اشتراط سجلّي PRAYER/HALAQA من HR
-- ويبقي: اكتمال الدرجات الفعلية، اكتمال الذاتي، ملاحظة المدير، نطاق المجموع.
create or replace function public.get_kpi_validation_errors(p_evaluation_id uuid)
returns text[]
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_eval public.kpi_evaluations;
  v_errors text[] := array[]::text[];
  v_total numeric;
begin
  select * into strict v_eval from public.kpi_evaluations where id = p_evaluation_id;

  if exists(
    select 1 from public.kpi_criteria c
    where c.template_id = v_eval.template_id
      and public.kpi_effective_score(v_eval.id, c.id) is null
  ) then
    v_errors := array_append(v_errors, 'لم تكتمل درجات البنود السبعة.');
  end if;

  if not exists(
    select 1
    from public.kpi_scores s
    join public.kpi_criteria c on c.id = s.criterion_id
    where s.evaluation_id = v_eval.id
      and s.reviewer_stage = 'self'
    group by s.evaluation_id
    having count(distinct s.criterion_id) =
      (select count(*) from public.kpi_criteria where template_id = v_eval.template_id)
  ) then
    v_errors := array_append(v_errors, 'التقييم الذاتي للبنود غير مكتمل.');
  end if;

  if nullif(trim(coalesce(v_eval.manager_comment, '')), '') is null then
    v_errors := array_append(v_errors, 'ملاحظة المدير مطلوبة قبل الاعتماد النهائي.');
  end if;

  v_total := public.kpi_total_score(p_evaluation_id);
  if v_total < 0 or v_total > 100 then
    v_errors := array_append(v_errors, 'المجموع النهائي يجب أن يكون بين صفر و100.');
  end if;

  return v_errors;
end $$;

revoke all on function public.get_kpi_validation_errors(uuid) from public, anon;
grant  execute on function public.get_kpi_validation_errors(uuid) to authenticated;

-- ─── 7) الإرجاع: من المدير إلى الموظف فقط ──────────────────────────────────
create or replace function public.return_kpi_stage(p_evaluation_id uuid,p_target_stage text,p_note text)
returns public.kpi_evaluations
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_eval public.kpi_evaluations; v_cycle public.kpi_cycles;
begin
 if length(trim(coalesce(p_note,'')))<5 then raise exception 'RETURN_REASON_REQUIRED'; end if;
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 if v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle) then raise exception 'KPI_CYCLE_CLOSED'; end if;
 if p_target_stage<>'self' or v_eval.current_stage<>'manager_review' then
   raise exception 'KPI_FLOW_SIMPLIFIED: الإرجاع المتاح فقط manager_review → self' using errcode='22023';
 end if;
 if not public.kpi_can_approve(v_eval) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 delete from public.kpi_scores where evaluation_id=v_eval.id and reviewer_stage='manager';
 update public.kpi_evaluations set
  stage='self',current_stage='self',workflow_status='OPEN_FOR_SELF_EVALUATION',
  manager_comment=null,manager_approved_at=null,manager_approved_by=null,
  version=version+1,updated_at=now()
 where id=v_eval.id returning * into v_eval;
 perform public.log_audit_event('kpi.stage_returned','workflow','notice','kpi_evaluations',v_eval.id,
  'إعادة التقييم للموظف (0470)',p_note,null);
 return v_eval;
end $$;

-- ─── 8) الصلاحيات ──────────────────────────────────────────────────────────
revoke all on function public.advance_kpi_stage(uuid,text,jsonb,text) from public, anon;
grant  execute on function public.advance_kpi_stage(uuid,text,jsonb,text) to authenticated;
revoke all on function public.return_kpi_stage(uuid,text,text)           from public, anon;
grant  execute on function public.return_kpi_stage(uuid,text,text)       to authenticated;
revoke all on function public.acknowledge_kpi_evaluation(uuid,text,text)  from public, anon;
grant  execute on function public.acknowledge_kpi_evaluation(uuid,text,text) to authenticated;
revoke all on function public.kpi_resolve_approver_for_employee(uuid)    from public, anon;
grant  execute on function public.kpi_resolve_approver_for_employee(uuid) to authenticated;
revoke all on function public.create_kpi_cycle_admin(date,uuid,timestamptz,timestamptz,timestamptz,timestamptz,boolean,boolean) from public, anon;
grant  execute on function public.create_kpi_cycle_admin(date,uuid,timestamptz,timestamptz,timestamptz,timestamptz,boolean,boolean) to authenticated;

-- ─── 6.7) نموذج التقييم: قابلية تحرير بعقد 0470 ───────────────────────────
-- editableStage يخص فاعل المسار فقط (self / manager_review)، بينما
-- complianceEditable تُمكّن مراجع HR من إدخال الاستثناءات في أي مرحلة قبل القفل.
create or replace function public.get_kpi_evaluation_form(p_evaluation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_employee public.employees; v_cycle public.kpi_cycles;
 v_editable text; v_compliance_editable boolean:=false; v_locked boolean; v_criteria jsonb;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if not public.kpi_can_read_evaluation(p_evaluation_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into v_employee from public.employees where id=v_eval.employee_id;
 select * into v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 v_locked:=v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle);

 if not v_locked then
  if v_eval.current_stage='self' and v_eval.employee_id=public.current_employee_id()
     and (public.current_is_full_access() or public.has_permission('performance.kpi.self_assess')) then
   v_editable:='self';
  elsif v_eval.current_stage='manager_review' and public.kpi_can_approve(v_eval) then
   v_editable:='manager_review';
  end if;
  -- استثناءات HR متاحة في أي مرحلة غير مقفلة (0470)
  if not v_eval.locked and public.current_is_hr_reviewer() then v_compliance_editable:=true; end if;
 end if;

 -- انتقالات حالة العرض
 if v_editable='manager_review' and v_eval.workflow_status='SUBMITTED_TO_DIRECT_MANAGER' then
  update public.kpi_evaluations set workflow_status='MANAGER_EVALUATION_IN_PROGRESS',updated_at=now() where id=v_eval.id returning * into v_eval;
  perform public.log_audit_event('kpi.manager.review_started','workflow','info','kpi_evaluations',v_eval.id,'بدء المدير المباشر مراجعة التقييم',null,null);
 end if;

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'code',c.code,'name',c.name_ar,'description',c.description,'sectionCode',c.section_code,
  'weight',c.weight,'maxScore',c.max_score,'sortOrder',c.sort_order,'sourceType',c.source_type,
  'evaluatorStage',c.evaluator_stage,'calculationMethod',c.calculation_method,
  'editable',case when v_editable='self' then true
                  when v_editable='manager_review' then c.evaluator_stage='manager'
                  else false end,
  'effectiveScore',public.kpi_effective_score(v_eval.id,c.id),
  'stageScores',coalesce((select jsonb_object_agg(s.reviewer_stage,jsonb_build_object('score',s.score,'note',s.note)) from public.kpi_scores s where s.evaluation_id=v_eval.id and s.criterion_id=c.id),'{}')
 ) order by c.sort_order),'[]'::jsonb) into v_criteria from public.kpi_criteria c where c.template_id=v_eval.template_id;

 return jsonb_build_object(
  'id',v_eval.id,'employeeId',v_eval.employee_id,'employeeName',v_employee.full_name_ar,'employeeCode',v_employee.employee_code,
  'periodMonth',v_cycle.period_month,'currentStage',v_eval.current_stage,'workflowStatus',v_eval.workflow_status,'editableStage',v_editable,
  'complianceEditable',v_compliance_editable,
  'locked',v_locked,'finalScore',v_eval.final_score,'finalRating',v_eval.final_rating,'criteria',v_criteria,
  'parallelFlow',false,'hrCompleted',v_eval.hr_completed,'managerCompleted',v_eval.manager_completed,'version',v_eval.version,
  'cycle',jsonb_build_object('id',v_cycle.id,'status',v_cycle.status,'scheduledOpenAt',v_cycle.scheduled_open_at,'deadlineAt',v_cycle.deadline_at,'extendedUntil',v_cycle.extended_until,'effectiveDeadline',public.kpi_effective_deadline(v_cycle)),
  'goals',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'title',g.title,'description',g.description,'targetValue',g.target_value,'achievedValue',g.achieved_value,'unit',g.unit,'weight',g.weight,'dueDate',g.due_date,'evidenceSource',g.evidence_source,'employeeNote',g.employee_note,'managerNote',g.manager_note,'status',g.status,'calculatedScore',g.calculated_score) order by g.created_at) from public.kpi_goals g where g.evaluation_id=v_eval.id),'[]'::jsonb),
  'session',(select jsonb_build_object('id',s.id,'scheduledAt',s.scheduled_at,'heldAt',s.held_at,'mode',s.mode,'discussionSummary',s.discussion_summary,'strengths',s.strengths,'improvementPoints',s.improvement_points,'nextMonthGoals',s.next_month_goals,'employeeNotes',s.employee_notes,'managerNotes',s.manager_notes,'employeeAttended',s.employee_attended,'managerAttended',s.manager_attended,'employeeConfirmedAt',s.employee_confirmed_at) from public.kpi_review_sessions s where s.evaluation_id=v_eval.id),
  'compliance',coalesce((select jsonb_agg(jsonb_build_object('metric',r.metric,'requiredCount',r.required_count,'actualCount',r.actual_count,'exemptCount',r.exempt_count,'cancelledCount',r.cancelled_count,'score',r.calculated_score,'note',r.note)) from public.kpi_compliance_records r where r.evaluation_id=v_eval.id),'[]'::jsonb),
  'attendance',(select jsonb_build_object('periodStart',a.period_start,'periodEnd',a.period_end,'lateCount',a.late_count,'earlyLeaveCount',a.early_leave_count,'unexcusedAbsenceCount',a.unexcused_absence_count,'shortagePenalty',a.shortage_penalty,'missingPunchCount',a.missing_punch_count,'score',a.score,'hasPendingItems',a.has_pending_items,'calculatedAt',a.calculated_at) from public.kpi_attendance_snapshots a where a.evaluation_id=v_eval.id),
  'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'criterionId',x.criterion_id,'type',x.evidence_type,'title',x.title,'description',x.description,'storagePath',x.storage_path,'externalUrl',x.external_url,'submittedStage',x.submitted_stage,'createdAt',x.created_at) order by x.created_at) from public.kpi_evidence x where x.evaluation_id=v_eval.id),'[]'::jsonb),
  'validationErrors',to_jsonb(public.get_kpi_validation_errors(v_eval.id)),
  'lastUpdatedAt',coalesce(v_eval.updated_at,v_eval.created_at)
 );
end $$;

revoke all on function public.get_kpi_evaluation_form(uuid) from public, anon;
grant  execute on function public.get_kpi_evaluation_form(uuid) to authenticated;

commit;
