-- ============================================================================
-- 0663: إصلاح شاشة المراقبة وشاشة التقارير اليومية في لوحة الإدارة
-- ============================================================================
-- 1) شاشة المراقبة (/admin/observability):
--    - المشكلة: الترحيل 0658 أنشأ دالة get_system_health(p_limit integer default 14)
--      مما أحدث تضارباً في التحميل الزائد (Function Overload Ambiguity) مع الدالة
--      الأصلية public.get_system_health() (بدون وسائط)، فأصبحت قاعدة البيانات
--      ترمي الخطأ 42725: function public.get_system_health() is not unique
--      عند استدعاء الواجهة لها دون وسائط، وتظهر شاشة "تعذر تحميل لوحة المراقبة".
--    - الحل: حذف الدالة الزائدة get_system_health(integer) ونقلها باسم مستقل
--      get_system_health_runs(p_limit integer default 14)، لتعود get_system_health()
--      فريدة وتعمل مباشرة وبشكل فوري كما تتوقع الواجهة.
--
-- 2) شاشة التقارير اليومية (/admin/hr/daily-reports):
--    - المشكلة: الترحيل 0617 (عزل العيادات) حذف بالخطأ حقلي 'comments' و'likers'
--      من كائن JSON العائد من get_public_daily_reports_feed.
--      ولأن مخطط التحقق Zod في واجهة الإدارة (shared-contracts/operations.ts)
--      يتطلب مصفوفة comments كعنصر إلزامي، فشل التحقق في الواجهة برمز خطأ Zod
--      وظهرت شاشة "تعذر تحميل التقارير".
--    - الحل: إعادة تعريف get_public_daily_reports_feed مع تضمين حقول 'comments'
--      و'likers' كاملة مع الحفاظ على عزل العيادات (is_clinic_staff_exempt).
-- ============================================================================

-- ─── 1) إصلاح لوحة المراقبة: فك تضارب get_system_health ─────────────────────
drop function if exists public.get_system_health(integer);

create or replace function public.get_system_health_runs(p_limit integer default 14)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.current_is_full_access() then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'runs', coalesce((
      select jsonb_agg(jsonb_build_object('ranAt', h.ran_at, 'ok', h.ok, 'checks', h.checks, 'failures', h.failures)
                       order by h.ran_at desc)
        from (select * from public.system_health_runs order by ran_at desc
              limit greatest(1, least(coalesce(p_limit, 14), 90))) h), '[]'::jsonb),
    'openAlerts', coalesce((
      select jsonb_agg(jsonb_build_object('key', a.alert_key, 'severity', a.severity, 'title', a.title,
                                          'lastSeenAt', a.last_seen_at, 'occurrences', a.occurrences)
                       order by a.last_seen_at desc)
        from public.system_alerts a where a.status = 'open'), '[]'::jsonb));
end;
$$;

comment on function public.get_system_health_runs(integer) is
  '0663: نتائج الفحص الصحي اليومي (0658) والتنبيهات المفتوحة — مفصولة لتفادي تعارض التوقيع مع get_system_health().';
revoke all on function public.get_system_health_runs(integer) from public, anon;
grant execute on function public.get_system_health_runs(integer) to authenticated, service_role;

revoke execute on function public.get_system_health() from public, anon;
grant execute on function public.get_system_health() to authenticated, service_role;

-- ─── 2) إصلاح التقارير اليومية: استعادة comments و likers ─────────────────────
create or replace function public.get_public_daily_reports_feed(
  p_limit integer default 50,
  p_before date default null::date
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid := public.current_employee_id();
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  -- تيم العيادات (غير المديرين) لا يرى التقارير اليومية إطلاقاً
  if public.is_clinic_staff_exempt(v_me) then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', dr.id,
    'employeeId', e.id,
    'employeeName', e.full_name_ar,
    'employeeCode', e.employee_code,
    'photoUrl', e.photo_url,
    'jobTitle', jt.name,
    'department', d.name,
    'managerName', mgr.full_name_ar,
    'reportDate', dr.report_date,
    'achievements', dr.achievements,
    'blockers', dr.blockers,
    'tomorrowPlan', dr.tomorrow_plan,
    'managerComment', dr.manager_comment,
    'reviewedByName', rv.full_name_ar,
    'reviewedAt', dr.reviewed_at,
    'createdAt', dr.created_at,
    'likesCount', (select count(*) from public.daily_report_likes l where l.report_id = dr.id),
    'isLikedByMe', exists(
      select 1 from public.daily_report_likes l
      where l.report_id = dr.id and l.employee_id = v_me
    ),
    'viewersCount', (select count(*) from public.daily_report_views v where v.report_id = dr.id),
    'viewers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', ve.id,
        'name', ve.full_name_ar,
        'photoUrl', ve.photo_url,
        'at', v.last_viewed_at
      ) order by v.last_viewed_at desc)
      from (
        select v2.employee_id, v2.last_viewed_at
        from public.daily_report_views v2
        where v2.report_id = dr.id
        order by v2.last_viewed_at desc
        limit 3
      ) v
      join public.employees ve on ve.id = v.employee_id
    ), '[]'::jsonb),
    'likers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', le.id,
        'name', le.full_name_ar,
        'photoUrl', le.photo_url,
        'at', l.created_at
      ) order by l.created_at desc)
      from public.daily_report_likes l
      join public.employees le on le.id = l.employee_id
      where l.report_id = dr.id
      limit 3
    ), '[]'::jsonb),
    'comments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'employeeId', c.employee_id,
        'employeeName', ce.full_name_ar,
        'comment', c.comment,
        'createdAt', c.created_at
      ) order by c.created_at asc)
      from public.daily_report_comments c
      join public.employees ce on ce.id = c.employee_id
      where c.report_id = dr.id
    ), '[]'::jsonb)
  ) order by dr.report_date desc, dr.created_at desc), '[]'::jsonb)
  into v_result
  from public.daily_reports dr
  join public.employees e on e.id = dr.employee_id
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments d on d.id = e.department_id
  left join public.departments dm on dm.id = e.department_id
  left join lateral (
    select mr.manager_employee_id
    from public.manager_relations mr
    where mr.employee_id = e.id
      and mr.relation_type = 'primary'
      and mr.effective_from <= now()
      and (mr.effective_to is null or mr.effective_to > now())
    order by mr.effective_from desc
    limit 1
  ) mrel on true
  left join public.employees mgr on mgr.id = coalesce(mrel.manager_employee_id, dm.manager_id)
  left join public.employees rv on rv.id = dr.reviewed_by
  where not e.is_deleted
    and (p_before is null or dr.report_date < p_before)
  limit coalesce(p_limit, 50);

  return v_result;
end;
$function$;

comment on function public.get_public_daily_reports_feed(integer, date) is
  '0663: تغذية التقارير اليومية مع likers وcomments لعقد shared-contracts وواجهات الويب والموبايل.';
revoke execute on function public.get_public_daily_reports_feed(integer, date) from public, anon;
grant execute on function public.get_public_daily_reports_feed(integer, date) to authenticated, service_role;
