-- pgTAP: V23 — leaves escalation split (migration 0171)
-- تتحقق من: إعدادات التصعيد، دالة get_escalation_hours، المشغل
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(10);

-- ═══════════════════════════════════════════════════════════════════════
-- 1) إعدادات التصعيد الجديدة موجودة
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  exists(select 1 from public.settings
    where scope = 'organization' and category = 'leave'
      and key = 'leave_escalation_hours_executive'),
  'setting leave_escalation_hours_executive exists'
);

select ok(
  exists(select 1 from public.settings
    where scope = 'organization' and category = 'leave'
      and key = 'leave_escalation_hours_other'),
  'setting leave_escalation_hours_other exists'
);

-- القيم الافتراضية
select is(
  (select (value #>> '{}') from public.settings
   where scope = 'organization' and category = 'leave'
     and key = 'leave_escalation_hours_executive'),
  '6',
  'executive escalation default is 6 hours'
);

select is(
  (select (value #>> '{}') from public.settings
   where scope = 'organization' and category = 'leave'
     and key = 'leave_escalation_hours_other'),
  '12',
  'other escalation default is 12 hours'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 2) الإعداد القديم مُعلّم deprecated
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  coalesce(
    (select description like '%DEPRECATED%' from public.settings
     where scope = 'organization' and key = 'leave_approval_escalation_hours'),
    true  -- إذا لم يكن الإعداد القديم موجوداً أصلاً
  ),
  'old leave_approval_escalation_hours is deprecated or absent'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 3) الدالة get_escalation_hours موجودة
-- ═══════════════════════════════════════════════════════════════════════
select has_function('public', 'get_escalation_hours', array['uuid'],
  'get_escalation_hours(uuid) function exists');

select function_returns('public', 'get_escalation_hours', array['uuid'], 'integer',
  'get_escalation_hours returns integer');

-- دالة بدون مدير محدد → 12 ساعة (غير تنفيذي)
select is(
  public.get_escalation_hours('00000000-0000-4000-8000-000000000099'::uuid),
  12,
  'non-existent manager gets 12-hour default (non-executive)'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 4) المشغل موجود على requests
-- ═══════════════════════════════════════════════════════════════════════
select has_trigger('public', 'requests', 'trg_adjust_escalation_deadline',
  'escalation deadline trigger exists on requests');

-- ═══════════════════════════════════════════════════════════════════════
-- 5) الدالة تملك search_path مثبت
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  exists(
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname = 'get_escalation_hours'
    and exists(select 1 from unnest(p.proconfig) c where c like 'search_path=%')
  ),
  'get_escalation_hours has pinned search_path'
);

select * from finish();
rollback;
