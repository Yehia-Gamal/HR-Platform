-- ============================================================================
-- 0484: إصلاح بيانات الإشعارات المكسورة الترميز (mojibake) في تخزين الإنتاج
-- ============================================================================
-- الجذر: الإشعارات النصية المخزنة حُفظت بترميز مزدوج
-- (العربي → UTF-8 بايتات → سلّمها مسار نشر مكسور قرأها كـ LATIN1 ثم أُعيد
-- ترميزها UTF-8)، فظهرت على الويب والموبايل كرموز غريبة (Ø Ù ª †).
--
-- الحل: دالة reverse_latin1_segments تعكس المقاطع المكسورة فقط
-- (encode LATIN1 ثم decode UTF8) بشكل انتقائي فلا تُفسد النص العربي السليم.
-- ثم تُطبّق على الإشعارات وأي صفوف حاملة للنمط.
--
-- ملاحظة: إصلاح مصادر الدوال الـ299 تمت في 0480؛ هذه تعالج صفوف البيانات.
-- ============================================================================

-- ─── دالة العكس الانتقائي ───
create or replace function public.reverse_latin1_segments(t text)
returns text
language plpgsql
immutable
as $rev$
declare
  -- النمط: بايت بداية مزدوج (C0-FF) ثم 2+ بايت متابعة (80-BF) = ترميز مزدوج
  pat text := '[\u00C0-\u00FF][\u0080-\u00BF][\u0080-\u00BF]+';
  m record;
begin
  if t is null or t !~ pat then
    return t;
  end if;
  for m in
    select (regexp_matches(t, pat, 'g'))[1] as seg
  loop
    begin
      t := replace(t, m.seg, convert_from(convert_to(m.seg, 'LATIN1'), 'UTF8'));
    exception when others then
      null; -- مقطع لا يمكن عكسه — اتركه
    end;
  end loop;
  return t;
end;
$rev$;

-- ─── إصلاح صفوف الإشعارات ───
update public.notifications
set title = public.reverse_latin1_segments(title),
    body  = public.reverse_latin1_segments(body)
where title ~ '[\u00C0-\u00FF][\u0080-\u00BF][\u0080-\u00BF]+'
   or body  ~ '[\u00C0-\u00FF][\u0080-\u00BF][\u0080-\u00BF]+';

-- ─── إصلاح الإعلانات (إن وجدت صفوف مكسورة) ───
update public.announcements
set title = public.reverse_latin1_segments(title),
    body  = public.reverse_latin1_segments(body)
where title ~ '[\u00C0-\u00FF][\u0080-\u00BF][\u0080-\u00BF]+'
   or body  ~ '[\u00C0-\u00FF][\u0080-\u00BF][\u0080-\u00BF]+';
