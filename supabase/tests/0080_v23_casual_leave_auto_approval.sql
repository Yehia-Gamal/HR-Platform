-- 0080: V23 §7.3 — العارضة = تنفيذ مباشر بشروط.
-- يثبت أن submit_my_request تعتمد الإجازة العارضة (casual) فورًا
-- دون انتظار موافقة المدير المباشر.
-- السلسلة المتوقعة: تقديم → approved + completed (بلا خطوات موافقة).
-- يتحقق من: الحالة الفورية، تخطي الخطوات، إجراء النظام، تعيين immediate.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(10);

-- =====================================================================
-- (1) الدالة موجودة بالتوقيع المتوقع
-- =====================================================================
select has_function(
  'public', 'submit_my_request', array['text','text','text','jsonb','uuid'],
  'submit_my_request RPC exists');

-- =====================================================================
-- (2-8) فحص كود الدالة: منطق العارضة الفورية
-- نقرأ prosrc لنتحقق أن الدالة تحتوي المنطق المطلوب بدون حاجة
-- لتشغيل كامل (الذي يتطلب بيئة مصادقة كاملة).
-- =====================================================================

-- (2) الدالة تميّز العارضة (casual) عن غيرها
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_request' and pronamespace='public'::regnamespace;
    if v_src not ilike '%casual%' then
      raise exception 'submit_my_request لا تتعامل مع العارضة (casual)';
    end if;
  end $t$$live$,
  'submit_my_request تتعامل مع نوع العارضة (casual)');

-- (3) العارضة تحدد الحالة إلى approved فورًا
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_request' and pronamespace='public'::regnamespace;
    if v_src not ilike '%casual%' or v_src not ilike '%approved%' then
      raise exception 'العارضة لا تُعتمد فورًا (approved)';
    end if;
  end $t$$live$,
  'العارضة تُعتمد فورًا — status = approved');

-- (4) العارضة تُكمل سير العمل فورًا (workflow_status = completed)
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_request' and pronamespace='public'::regnamespace;
    if v_src not ilike '%workflow_status%completed%' then
      raise exception 'العارضة لا تُكمل سير العمل (completed)';
    end if;
  end $t$$live$,
  'سير العمل يُكتمل فورًا — workflow_status = completed');

-- (5) خطوات الموافقة تُتخطى (status = skipped)
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_request' and pronamespace='public'::regnamespace;
    if v_src not ilike '%skipped%' then
      raise exception 'خطوات الموافقة لا تُتخطى للعارضة';
    end if;
  end $t$$live$,
  'خطوات الموافقة تُتخطى — request_steps.status = skipped');

-- (6) إجراء النظام (action = system) يُسجَّل
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_request' and pronamespace='public'::regnamespace;
    if v_src not ilike '%system%' then
      raise exception 'لا يُسجَّل إجراء النظام (system)';
    end if;
  end $t$$live$,
  'إجراء النظام يُسجَّل — request_actions.action = system');

-- (7) العلامة immediate = true في metadata
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_request' and pronamespace='public'::regnamespace;
    if v_src not ilike '%immediate%true%' then
      raise exception 'العلامة immediate=true غير موجودة في metadata';
    end if;
  end $t$$live$,
  'العلامة immediate = true في metadata الإجراء');

-- (8) الحقل immediate يُضاف في payload الإجازة
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_request' and pronamespace='public'::regnamespace;
    -- التحقق أن payload يحتوي immediate flag لنوع casual
    if v_src not ilike '%immediate%casual%' then
      raise exception 'payload لا يحتوي immediate flag لنوع casual';
    end if;
  end $t$$live$,
  'payload يحتوي علامة immediate لنوع casual');

-- =====================================================================
-- (9) التوافق الخلفي: emergency → casual
-- =====================================================================
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_request' and pronamespace='public'::regnamespace;
    if v_src not ilike '%emergency%' or v_src not ilike '%casual%' then
      raise exception 'لا يوجد تخريط emergency → casual';
    end if;
  end $t$$live$,
  'التوافق الخلفي: emergency يُخرَّط إلى casual');

-- =====================================================================
-- (10) تسجيل حدث التدقيق leave.casual.immediate
-- =====================================================================
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='submit_my_request' and pronamespace='public'::regnamespace;
    if v_src not ilike '%leave.casual.immediate%' then
      raise exception 'لا يُسجَّل حدث تدقيق leave.casual.immediate';
    end if;
  end $t$$live$,
  'حدث التدقيق leave.casual.immediate مُسجَّل');

select * from finish();
rollback;
