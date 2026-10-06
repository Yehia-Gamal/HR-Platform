-- ═══════════════════════════════════════════════════════════════
-- 0649: إغلاق تسريب محتوى لجنة النزاعات + قفل جداول تدقيق مُقسَّمة غير مستخدمة
--
-- (1) P0 خصوصية — لكل جدول من جداول النزاعات الثمانية التالية سياستا SELECT:
--       • *_select : مُحكمة عمداً — مستوى الرؤية (parties / complainant /
--                    respondent / committee_only)، عضوية اللجنة، can_access_dispute.
--       • *_read   : بقايا قديمة (0030 / 0059 / 0217) بـ `using (true)`.
--     السياستان PERMISSIVE، وPostgreSQL يجمعهما بـ OR، فـ `using (true)` **يُلغي
--     السياسة المُحكمة كلياً**: أي موظف مسجّل يقرأ عبر
--       supabase.from('dispute_statements').select('*')
--     كل إفادة في كل نزاع — حتى المقيّدة بالمشتكي وحده أو بالمشكو منه وحده —
--     وكل قرار ومبرّره، ومن اشتكى على من.
--     dispute_cases نفسها محمية عبر can_access_dispute (موثّق في
--     RLS_PUBLIC_REFERENCE_ALLOWLIST.md: «قضايا شخصية»)، لكن المحتوى في الجداول
--     الفرعية كان مكشوفاً.
--
--     تحقّقٌ قبل الحذف (2026-10-06، قاعدة محلية @0641):
--       • الواجهة لا تقرأ هذه الجداول مباشرة (صفر from('dispute_…') في apps/).
--       • صفر دوال SECURITY INVOKER أو views أو سياسات على جداول أخرى تقرأها
--         في سياق المستخدم.
--       • سياسة dispute_statements_select تستعلم dispute_parties للمشكو منه —
--         صفّه هو، المسموح عبر dispute_parties_select (employee_id = الموظف).
--       • اختبارات النزاعات الستة (0018/0037/0054/0066/0083/0537) — 97 تأكيداً.
--
-- (2) P2 — audit_events_partitioned وأقسامه (0315) بلا RLS، و authenticated يملك
--     SELECT و INSERT عليها. الجدول فارغ ولا شيء يكتب فيه (سجل التدقيق الفعلي
--     audit_events محمي)، لكنه سطح API مفتوح: أي موظف يُدرج فيه ما يشاء.
--     نفعّل RLS بلا سياسات ونسحب الصلاحيات من anon/authenticated على الأب وكل
--     الأقسام الحالية (عبر pg_inherits). service_role والمالك يبقيان.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ═══════════════════════════════════════════════
-- 1. حذف سياسات القراءة المفتوحة على جداول النزاعات
-- ═══════════════════════════════════════════════
drop policy if exists dispute_statements_read           on public.dispute_statements;
drop policy if exists dispute_decisions_read            on public.dispute_decisions;
drop policy if exists dispute_parties_read              on public.dispute_parties;
drop policy if exists dispute_appeals_read              on public.dispute_appeals;
drop policy if exists dispute_actions_read              on public.dispute_actions;
drop policy if exists dispute_settlements_read          on public.dispute_settlements;
drop policy if exists dispute_decision_receipts_read    on public.dispute_decision_receipts;
drop policy if exists dispute_session_participants_read on public.dispute_session_participants;

-- ═══════════════════════════════════════════════
-- 2. قفل audit_events_partitioned وكل أقسامه الحالية
-- ═══════════════════════════════════════════════
do $lock$
declare
  r record;
begin
  if to_regclass('public.audit_events_partitioned') is null then
    return;
  end if;

  for r in
    select 'public.audit_events_partitioned'::regclass as rel
    union
    select i.inhrelid::regclass
      from pg_inherits i
     where i.inhparent = 'public.audit_events_partitioned'::regclass
  loop
    execute format('alter table %s enable row level security', r.rel);
    execute format('revoke all on table %s from public, anon, authenticated', r.rel);
  end loop;
end $lock$;

commit;
