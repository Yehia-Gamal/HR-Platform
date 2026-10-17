-- ============================================================================
-- 0639: إعادة مفاتيح likers وcomments إلى تغذية التقارير اليومية المعلنة
-- ============================================================================
-- المشكلة: إعادة كتابة get_public_daily_reports_feed في 0617 (عزل العيادات)
--   حذفت بالخطأ مفتاحين كانا في العقد الأصلي (0425/0478/0480/0483):
--     1) 'likers'      — اسم أول معجب يظهر في الاختبار 0425 (feed يعرض اسم أول معجب).
--     2) 'comments'    — تقرأها واجهة الموبايل مباشرة
--                        (daily_reports_feed_page.dart:458 item['comments']).
--  _likesCount وبقية المفاتيح بقيت كما هي — الحذف غير مقصود (خصوصية العيادات
--  تعالَج عبر is_clinic_staff_exempt في بداية الدالة، وأسماء المشاهدين بقيت معروضة).
-- النتيجة الحالية في الإنتاج: مصفوفة المعجبين والتعليقات فارغة دائماً في الموبايل.
-- الإصلاح: استبدال كلي بالنسخة الحالية (0617) + إرجاع المفتاحين بنفس شكل 0483.

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

  -- ★ تيم العيادات (غير المديرين) لا يرى التقارير اليومية إطلاقاً ★
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
    -- 0639: مفتاحان محذوفان في 0617 للاستهلاك في الموبايل + عقد 0425
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
  -- 0639: مدير الكاتب أولاً من manager_relations (عقد 0114) ثم departments.manager_id
  -- (0617 قرأتdepartments وحدها فرجعت NULL لمن ليس له مدير قسم)
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
  '0639: تغذية التقارير (0617 عزل العيادات) + likers/comments المفقودين منذ 0617 لعقد 0425 وواجهة الموبايل.';
revoke execute on function public.get_public_daily_reports_feed(integer, date) from public, anon;
grant execute on function public.get_public_daily_reports_feed(integer, date) to authenticated, service_role;
