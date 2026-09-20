-- =====================================================================
-- 0533: ضبط دقيق للاستثناءات الإدارية ومنع التطابق الزائد
-- =====================================================================
-- 1) حصر الاستثناء الدائم من الحضور والانصراف والغرامات بدقة متناهية بالـ UUID والكود:
--    - ألشيخ محمد يوسف (المدير التنفيذي) [7b0740fa-66ba-4616-8674-3dbd8e14109e, 886f4942-c469-4a03-8f02-659fd02c4a02]
--    - محمد عبدالباسط (أبو عمار) [767eae8e-e7be-458e-a6ca-879414e46b08]
--    - عبدالعزيز طارق محمود الباسل [fad7044c-fe47-4db3-b7bb-54856e7ba851]
--    - عبدالله احمد نصر [c61c2a26-19db-49fb-ad8b-ace2d8a765af]
-- 2) استثناء دائم من الغرامات فقط (مع بقاء تسجيل الحضور):
--    - هاني احمد نصير [8e21d363-f87c-4c80-b06d-1b84a2dd3804]
-- 3) إزالة الاستثناء الخاطئ الناتج عن التشابه الجزئي للأسماء في 0532 عن:
--    - عبد الملك محمد يوسف [cc893835-ceb3-44b8-b4c4-9802c38e3195] (+201149740716)
--    - ياسين طارق الباسل [41751008-afdd-4537-a6db-05021f1c1e00] (+201127260359)
-- 4) تحديث دوال فحص الإعفاء public.is_employee_attendance_exempt و public.is_employee_penalty_exempt
-- 5) استعادة الغرامات الملغاة بالخطأ للموظفين غير المعفيين
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) تصحيح حقول الإعفاء في جدول public.employees
-- ─────────────────────────────────────────────────────────────────────

-- تصفير الإعفاء لأي موظف غير الخمسة المحددين بالاسم من الإدارة
update public.employees
   set is_attendance_exempt = false,
       is_penalty_exempt = false,
       updated_at = now()
 where id not in (
   '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- ألشيخ محمد يوسف
   '886f4942-c469-4a03-8f02-659fd02c4a02', -- ألشيخ محمد يوسف (أرشيف/تنفيذي)
   '767eae8e-e7be-458e-a6ca-879414e46b08', -- محمد عبدالباسط ( ابو عمار )
   'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- عبدالعزيز طارق محمود الباسل
   'c61c2a26-19db-49fb-ad8b-ace2d8a765af', -- عبدالله احمد نصر
   '8e21d363-f87c-4c80-b06d-1b84a2dd3804'  -- هاني احمد نصير
 )
 and (is_attendance_exempt = true or is_penalty_exempt = true);

-- تعيين الإعفاء الشامل (حضور وغرامات) للأربعة المحددين فقط
update public.employees
   set is_attendance_exempt = true,
       is_penalty_exempt = true,
       updated_at = now()
 where id in (
   '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- ألشيخ محمد يوسف
   '886f4942-c469-4a03-8f02-659fd02c4a02', -- ألشيخ محمد يوسف
   '767eae8e-e7be-458e-a6ca-879414e46b08', -- محمد عبدالباسط ( ابو عمار )
   'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- عبدالعزيز طارق محمود الباسل
   'c61c2a26-19db-49fb-ad8b-ace2d8a765af'  -- عبدالله احمد نصر
 );

-- تعيين إعفاء الغرامات فقط (حضور غير معفى) لهاني احمد نصير
update public.employees
   set is_attendance_exempt = false,
       is_penalty_exempt = true,
       updated_at = now()
 where id = '8e21d363-f87c-4c80-b06d-1b84a2dd3804';


-- ─────────────────────────────────────────────────────────────────────
-- 2) تحديث دالة فحص الإعفاء من الحضور والانصراف بدقة
-- ─────────────────────────────────────────────────────────────────────

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

  -- 1. فحص المدير التنفيذي
  if public.is_employee_executive(p_employee_id) then
    return true;
  end if;

  -- 2. فحص السجل في جدول employees
  select id, employee_code, full_name_ar, is_attendance_exempt into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  if coalesce(v_rec.is_attendance_exempt, false) = true then
    return true;
  end if;

  -- 3. شبكة أمان بالمعرفات والأكواد والأسماء الصريحة فقط (دون تعميم جزئي)
  if p_employee_id in (
    '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- ألشيخ محمد يوسف
    '886f4942-c469-4a03-8f02-659fd02c4a02', -- ألشيخ محمد يوسف
    '767eae8e-e7be-458e-a6ca-879414e46b08', -- محمد عبدالباسط ( ابو عمار )
    'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- عبدالعزيز طارق محمود الباسل
    'c61c2a26-19db-49fb-ad8b-ace2d8a765af'  -- عبدالله احمد نصر
  ) or v_rec.employee_code in ('+201121622820', 'EXE001', '+201226905602', '+201000867705', '+201016664229')
    or v_rec.full_name_ar ilike '%ألشيخ محمد يوسف%'
    or v_rec.full_name_ar ilike '%الشيخ محمد يوسف%'
    or v_rec.full_name_ar ilike '%ابو عمار%'
    or v_rec.full_name_ar ilike '%عبدالعزيز%الباسل%'
    or v_rec.full_name_ar ilike '%عبدالله%نصر%' then
    return true;
  end if;

  return false;
end;
$$;

comment on function public.is_employee_attendance_exempt(uuid) is
  '0533: فحص دقيق للإعفاء الدائم من الحضور والانصراف للأشخاص المحددين إدارياً فقط';

grant execute on function public.is_employee_attendance_exempt(uuid) to authenticated, anon;


-- ─────────────────────────────────────────────────────────────────────
-- 3) تحديث دالة فحص الإعفاء من الغرامات بدقة
-- ─────────────────────────────────────────────────────────────────────

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

  -- 1. أي موظف معفى من الحضور فهو معفى حكماً من الغرامات
  if public.is_employee_attendance_exempt(p_employee_id) then
    return true;
  end if;

  -- 2. فحص السجل في جدول employees
  select id, employee_code, full_name_ar, is_penalty_exempt into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  if coalesce(v_rec.is_penalty_exempt, false) = true then
    return true;
  end if;

  -- 3. فحص هاني احمد نصير وشبكة أمان خاصة به فقط
  if p_employee_id = '8e21d363-f87c-4c80-b06d-1b84a2dd3804'
     or v_rec.employee_code = '+201012141949'
     or v_rec.full_name_ar ilike '%هاني%نصير%' then
    return true;
  end if;

  return false;
end;
$$;

comment on function public.is_employee_penalty_exempt(uuid) is
  '0533: فحص دقيق للإعفاء الدائم من الغرامات الفورية للأشخاص المحددين إدارياً فقط';

grant execute on function public.is_employee_penalty_exempt(uuid) to authenticated, anon;


-- ─────────────────────────────────────────────────────────────────────
-- 4) استعادة الغرامات الملغاة بالخطأ للموظفين غير المعفيين
-- ─────────────────────────────────────────────────────────────────────

-- أ) استعادة غرامة عبد الملك محمد يوسف ليوم 20-09
update public.instant_attendance_penalties
   set status = 'pending_payment',
       notes = 'تأخير عن موعد العمل (10:00 ص) — لم يسجل بصمة الحضور حتى الآن (11:30 AM)',
       updated_at = now()
 where id = '97970643-1084-43d6-b4a9-7f771d6e25ba';

-- ب) استعادة غرامة ياسين طارق الباسل ليوم 20-09
update public.instant_attendance_penalties
   set status = 'pending_payment',
       notes = 'تأخير عن موعد العمل (10:00 ص) — لم يسجل بصمة الحضور حتى الآن (11:30 AM)',
       updated_at = now()
 where id = '583a0b3c-8c63-41a0-82ae-24273e3add4b';

-- ج) استعادة غرامة ياسين طارق الباسل المضاعفة ليوم 19-09
update public.instant_attendance_penalties
   set status = 'doubled',
       escalation_level = 'doubled',
       current_amount = 500.00,
       notes = 'تأخير عن موعد العمل (10:00 ص) — لم يسجل بصمة الحضور حتى الآن (07:50 PM)',
       updated_at = now()
 where id = '05e0ee64-24f4-4bda-9f78-804c3a832deb';

commit;
