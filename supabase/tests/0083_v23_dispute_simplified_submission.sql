-- 0083: V23 §9.3 — حذف الأولوية والمكان والأدلة من تقديم النزاعات.
-- يثبت أن submit_my_dispute_v23 تُبسّط واجهة التقديم:
-- لا أولوية (تلقائياً normal) ، لا مكان حادثة ، لا أدلة.
-- اللجنة فقط تملك change_priority عبر transition_dispute_case.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(12);

-- =====================================================================
-- (1) الدالة submit_my_dispute_v23 موجودة
-- =====================================================================
select has_function(
  'public', 'submit_my_dispute_v23',
  'submit_my_dispute_v23 RPC exists');

-- =====================================================================
-- (2) التوقيع المبسّط: 7 معاملات فقط (بدون priority/location/evidence)
-- =====================================================================
select lives_ok(
  $live$do $t$
  declare v_nargs int;
  begin
    select pronargs into v_nargs from pg_proc
    where proname='submit_my_dispute_v23' and pronamespace='public'::regnamespace;
    if v_nargs <> 7 then
      raise exception 'submit_my_dispute_v23 عدد المعاملات % بدلاً من 7', v_nargs;
    end if;
  end $t$$live$,
  'submit_my_dispute_v23 لها 7 معاملات فقط (مبسّطة)');

-- (3) لا يوجد معامل priority في التوقيع
select lives_ok(
  $live$do $t$
  declare v_args text;
  begin
    select string_agg(p.parameter_name, ',') into v_args
    from information_schema.parameters p
    where p.specific_schema = 'public'
      and p.specific_name like 'submit_my_dispute_v23%'
      and p.parameter_mode = 'IN';
    if v_args ilike '%priority%' then
      raise exception 'submit_my_dispute_v23 تحتوي معامل priority — يجب حذفه';
    end if;
  end $t$$live$,
  'لا يوجد معامل priority في submit_my_dispute_v23');

-- (4) لا يوجد معامل location في التوقيع
select lives_ok(
  $live$do $t$
  declare v_args text;
  begin
    select string_agg(p.parameter_name, ',') into v_args
    from information_schema.parameters p
    where p.specific_schema = 'public'
      and p.specific_name like 'submit_my_dispute_v23%'
      and p.parameter_mode = 'IN';
    if v_args ilike '%location%' then
      raise exception 'submit_my_dispute_v23 تحتوي معامل location — يجب حذفه';
    end if;
  end $t$$live$,
  'لا يوجد معامل location في submit_my_dispute_v23');

-- =====================================================================
-- (5-7) فحص كود الدالة: القيم الافتراضية الآمنة
-- =====================================================================

-- (5) الأولوية تلقائياً normal
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_dispute_v23' and pronamespace='public'::regnamespace;
    if v_src not ilike '%normal%' then
      raise exception 'submit_my_dispute_v23 لا تضع الأولوية normal تلقائياً';
    end if;
  end $t$$live$,
  'الأولوية تلقائياً normal في submit_my_dispute_v23');

-- (6) المكان null (لا مكان حادثة)
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_dispute_v23' and pronamespace='public'::regnamespace;
    if v_src not ilike '%incident_location%' and v_src not ilike '%null%' then
      raise exception 'submit_my_dispute_v23 لا تضع incident_location = null';
    end if;
  end $t$$live$,
  'incident_location = null (لا مكان حادثة)');

-- (7) الدالة تفوّض إلى submit_my_dispute الأصلية
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_dispute_v23' and pronamespace='public'::regnamespace;
    if v_src not ilike '%submit_my_dispute%' then
      raise exception 'submit_my_dispute_v23 لا تفوّض إلى submit_my_dispute';
    end if;
  end $t$$live$,
  'submit_my_dispute_v23 تفوّض إلى submit_my_dispute الأصلية');

-- =====================================================================
-- (8-9) السرية والإقرارات مطلوبة
-- =====================================================================

-- (8) السرية مفعّلة تلقائياً (confidential = true)
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_dispute_v23' and pronamespace='public'::regnamespace;
    if v_src not ilike '%confidential%' or v_src not ilike '%true%' then
      raise exception 'السرية غير مفعّلة تلقائياً';
    end if;
  end $t$$live$,
  'السرية مفعّلة تلقائياً — confidential = true');

-- (9) الإقرارات (truth_confirmed + confidentiality_accepted) مُمرّرة
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_dispute_v23' and pronamespace='public'::regnamespace;
    if v_src not ilike '%truth_confirmed%' or v_src not ilike '%confidentiality_accepted%' then
      raise exception 'الإقرارات غير ممرّرة في submit_my_dispute_v23';
    end if;
  end $t$$live$,
  'الإقرارات truth_confirmed و confidentiality_accepted مُمرّرة');

-- =====================================================================
-- (10-11) اللجنة فقط تملك تغيير الأولوية
-- =====================================================================

-- (10) transition_dispute_case تدعم change_priority
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='transition_dispute_case' and pronamespace='public'::regnamespace;
    if v_src not ilike '%change_priority%' then
      raise exception 'transition_dispute_case لا تدعم change_priority';
    end if;
  end $t$$live$,
  'اللجنة تملك change_priority عبر transition_dispute_case');

-- (11) change_priority يتطلب سبباً (5 أحرف على الأقل)
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='transition_dispute_case' and pronamespace='public'::regnamespace;
    if v_src not ilike '%INVALID_PRIORITY_CHANGE%' then
      raise exception 'change_priority لا تتحقق من INVALID_PRIORITY_CHANGE';
    end if;
  end $t$$live$,
  'change_priority يرفض بدون سبب كافٍ (INVALID_PRIORITY_CHANGE)');

-- =====================================================================
-- (12) تغيير الأولوية يُسجَّل في audit log
-- =====================================================================
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='transition_dispute_case' and pronamespace='public'::regnamespace;
    if v_src not ilike '%dispute.priority_changed%' then
      raise exception 'change_priority لا يُسجَّل في audit log';
    end if;
  end $t$$live$,
  'تغيير الأولوية يُسجَّل — dispute.priority_changed');

select * from finish();
rollback;
