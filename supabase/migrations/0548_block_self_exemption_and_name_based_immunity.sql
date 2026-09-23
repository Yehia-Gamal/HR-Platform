-- ═══════════════════════════════════════════════════════════════
-- 0548: منع الإعفاء الذاتي من الحضور/الغرامات + إزالة مطابقة الإعفاء بالاسم
--
-- (1) P0 — أي موظف يُعفي نفسه من نظام الحضور والغرامات بالكامل:
--       supabase.from('employees')
--         .update({ is_penalty_exempt: true, is_attendance_exempt: true })
--         .eq('id', myId)
--     • سياسة employees_update (0014) تسمح بتحديث الصف الذاتي
--       `id = current_employee_id()` دون تحديد أعمدة.
--     • الحارس tg_employees_protect_job_fields (0004 — لم يُحدَّث منذها) قائمة
--       **حظر** لـ13 عموداً ويمرّر كل ما عداها؛ عمودا الإعفاء أُضيفا لاحقاً في
--       0532 فلم يدخلاها قط.
--     • ومدير يملك people.employee.update_basic يُعفي فريقه كله بنفس الطريقة.
--
-- (2) P0 — إعفاء وحصانة بالمطابقة الجزئية للاسم:
--     is_employee_attendance_exempt / is_employee_penalty_exempt (0547) تُعيد true
--     لأي `full_name_ar ilike '%يحيى%جمال%'` وأسماء شائعة أخرى ('%محمد يوسف%' …).
--     والأخطر tg_admin_immunity_employees_fn (0547) تُعيد *كتابة* الصف عند أي
--     إدراج/تحديث: status='active', is_active=true, والإعفاءان = true — لكل من
--     يطابق الاسم. أي:
--       • كل موظف حقيقي اسمه «يحيى … جمال» يصبح محصّناً معفياً بمجرد لمس سجلّه.
--       • وأي موظف نشط يُعيد تسمية نفسه (الاسم خارج قائمة 0004) ينال الحصانة.
--     كل شخص مقصود في هذه القوائم **له معرّف UUID صريح** فيها، و employee_code
--     فريد (ux_employees_employee_code) ومحظور التعديل الذاتي في 0004 — فهما
--     معرّفان آمنان. الاسم لا يضيف إلا إيجابيات كاذبة. ⇒ نحذف مطابقة الاسم فقط؛
--     المعرّف والكود والهاتف تبقى، فلا يتغير شيء لأي شخص مقصود.
--
-- (3) انحدار: 0547 أعادت منح anon على دالتي الإعفاء (بعد سحبه في 0542/0543) —
--     المرة الثالثة (0536، 0541، 0547). لا مستدعي لهما خارج قاعدة البيانات.
--
-- ما لا يمسّه هذا الإصلاح عمداً — يحتاج قرار المالك:
--   • is_active: تكتبه 14 دالة مشروعة، منها trg_fn_cancel_penalties_on_request_change
--     الذي يعمل تحت JWT الموظف عند تقديم طلب، ودوال تأكيد الدفع لأدوار HR بلا
--     update_sensitive. حمايته تكسر تقديم الإجازات وتأكيد الدفع.
--   • التعليق التلقائي عبر pg_cron لا يعمل: حارسا employees (0004) و profiles (0289)
--     يرفضان تغيير status بلا JWT (auth.role() = null)، و auto_escalate_instant_penalties
--     تلتقط الخطأ بـ `when others → return 0` فتُلغى كل تصعيدات الدورة بصمت. إصلاحه
--     يعني بدء تعليق موظفين فعلياً كل صباح — قرار عمل لا يُتخذ ضمنياً.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ═══════════════════════════════════════════════
-- 1. سحب anon (انحدار 0547)
-- ═══════════════════════════════════════════════
revoke execute on function public.is_employee_attendance_exempt(uuid) from anon, public;
revoke execute on function public.is_employee_penalty_exempt(uuid)    from anon, public;

-- ═══════════════════════════════════════════════
-- 2. حارس أعمدة الإعفاء والهوية الذاتية
--    يعمل بعد tg_admin_immunity_employees و trg_employees_protect_job_fields
--    (ترتيب أبجدي) فيرى الصف النهائي.
-- ═══════════════════════════════════════════════
create or replace function public.tg_employees_protect_exemption_identity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- مسارات موثوقة تمر:
  --   • auth.role() is null = لا JWT إطلاقاً = اتصال داخلي (pg_cron، migrations،
  --     اتصال قاعدة مباشر). لا يصل طلب PostgREST إلى تعديل employees بلا JWT:
  --     سياستا employees_insert/employees_update مقصورتان على `to authenticated`.
  --   • service_role (Edge Functions) — نفس نمط 0289.
  --   • full-access أو people.employee.update_sensitive.
  -- لا نستخدم current_user: داخل SECURITY DEFINER يساوي مالك الدالة دائماً.
  if auth.role() is null
     or auth.role() = 'service_role'
     or public.current_is_full_access()
     or public.has_permission('people.employee.update_sensitive') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.is_attendance_exempt or new.is_penalty_exempt then
      raise exception 'not authorized to set attendance/penalty exemption' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.is_attendance_exempt is distinct from old.is_attendance_exempt then
    raise exception 'not authorized to change is_attendance_exempt' using errcode = '42501';
  end if;
  if new.is_penalty_exempt is distinct from old.is_penalty_exempt then
    raise exception 'not authorized to change is_penalty_exempt' using errcode = '42501';
  end if;

  -- الهوية الذاتية: الاسم والهاتف يدخلان في مطابقة الإعفاء/الحصانة، وكانا
  -- قابلين للتعديل الذاتي عبر employees_update. يبقى تعديلهما متاحاً لمن يملك
  -- people.employee.update_basic (HR/المديرون) عبر update_employee_admin.
  if new.id = public.current_employee_id()
     and not public.has_permission('people.employee.update_basic') then
    if new.full_name_ar is distinct from old.full_name_ar then
      raise exception 'not authorized to change own full_name_ar' using errcode = '42501';
    end if;
    if new.phone_e164 is distinct from old.phone_e164 then
      raise exception 'not authorized to change own phone_e164' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.tg_employees_protect_exemption_identity() is
  '0548: يمنع غير المخوّلين من تعديل is_attendance_exempt/is_penalty_exempt، ومن تعديل اسمهم/هاتفهم ذاتياً. يمرّ: اتصال داخلي بلا JWT، service_role، full-access، update_sensitive.';

drop trigger if exists trg_employees_zz_protect_exemption_identity on public.employees;
create trigger trg_employees_zz_protect_exemption_identity
  before insert or update on public.employees
  for each row execute function public.tg_employees_protect_exemption_identity();

-- ═══════════════════════════════════════════════
-- 3. إزالة مطابقة الإعفاء/الحصانة بالاسم — نسخ كنونية من 0547
--    التغيير الوحيد: حذف أسطر `full_name_ar ilike …` (وتعليقات الأسماء).
-- ═══════════════════════════════════════════════

create or replace function public.is_employee_attendance_exempt(p_employee_id uuid)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
begin
  if p_employee_id is null then
    return false;
  end if;

  select id, employee_code, phone_e164, full_name_ar, is_attendance_exempt, user_id into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  -- 0. الحساب الرئيسي للنظام — بالمعرّف/الكود/الهاتف فقط، لا بالاسم
  if p_employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or v_rec.employee_code in ('+201154869616', '01154869616')
     or v_rec.phone_e164 in ('+201154869616', '01154869616')
     or v_rec.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960' then
    return true;
  end if;

  -- 1. فحص العلم في جدول employees
  if coalesce(v_rec.is_attendance_exempt, false) = true then
    return true;
  end if;

  -- 2. شبكة أمان كبار المسؤولين
  if p_employee_id in (
    '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- كبير مسؤولين
    '886f4942-c469-4a03-8f02-659fd02c4a02',
    '767eae8e-e7be-458e-a6ca-879414e46b08', -- كبير مسؤولين
    'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- كبير مسؤولين
    'c61c2a26-19db-49fb-ad8b-ace2d8a765af'  -- كبير مسؤولين
  ) or v_rec.employee_code in ('+201121622820', 'EXE001', '+201226905602', '+201000867705', '+201016664229') then
    return true;
  end if;

  return false;
end;
$$;

create or replace function public.is_employee_penalty_exempt(p_employee_id uuid)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
begin
  if p_employee_id is null then
    return false;
  end if;

  -- 0. الحساب الرئيسي للنظام — بالمعرّف/الكود/الهاتف فقط، لا بالاسم
  if p_employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9' then
    return true;
  end if;

  -- 1. أي موظف معفى من الحضور فهو معفى حكماً من الغرامات
  if public.is_employee_attendance_exempt(p_employee_id) then
    return true;
  end if;

  -- 2. فحص السجل في جدول employees
  select id, employee_code, phone_e164, full_name_ar, is_penalty_exempt, user_id into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  if v_rec.employee_code in ('+201154869616', '01154869616')
     or v_rec.phone_e164 in ('+201154869616', '01154869616')
     or v_rec.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960' then
    return true;
  end if;

  if coalesce(v_rec.is_penalty_exempt, false) = true then
    return true;
  end if;

  -- 3. استثناء بالمعرّف/الكود
  if p_employee_id = '8e21d363-f87c-4c80-b06d-1b84a2dd3804'
     or v_rec.employee_code = '+201012141949' then
    return true;
  end if;

  return false;
end;
$$;

create or replace function public.tg_admin_immunity_employees_fn()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if NEW.id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or NEW.phone_e164 in ('+201154869616', '01154869616')
     or NEW.employee_code in ('+201154869616', '01154869616')
     or NEW.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960' then
    NEW.status := 'active';
    NEW.is_active := true;
    NEW.is_attendance_exempt := true;
    NEW.is_penalty_exempt := true;
  end if;
  return NEW;
end;
$$;

revoke all on function public.is_employee_attendance_exempt(uuid) from public, anon;
grant execute on function public.is_employee_attendance_exempt(uuid) to authenticated, service_role;
revoke all on function public.is_employee_penalty_exempt(uuid) from public, anon;
grant execute on function public.is_employee_penalty_exempt(uuid) to authenticated, service_role;

commit;
