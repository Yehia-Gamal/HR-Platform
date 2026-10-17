-- ═══════════════════════════════════════════════════════════════════════════
-- 0633: إخلاء تقييمات المسار المتوازي القديمة العالقة
-- ═══════════════════════════════════════════════════════════════════════════
-- الواقع على الإنتاج (أعداد فقط، بلا PII): 4 تقييمات parallel_review بحالة
-- locked=true / workflow=OVERDUE داخل دورة status=locked.
--
-- السبب: مسار 0470 (0476) حوّل hr_review/manager_final فقط، وأبقى مراحل
-- parallel/secretary/executive كما هي (توثيق 0476:18-19) بينما يرفضها
-- advance_kpi_stage بـ KPI_FLOW_SIMPLIFIED → بطاقة تعرض زر «مراجعة متوازية»
-- يفتح صفحة للقراءة فقط (editableStage=null) — عقدة كاملة.
--
-- الحل: امتداد لتهجير 0476 (سطوره 27-34) + معكوس قفل process_kpi_cycle_schedule:
--   1) المراحل القديمة → manager_review مع فك القفل.
--   2) المقيّمات غير النهائية في نفس الدورات (self/manager كانت OVERDUE)
--      تُفكّ وتُستعاد حالتها المقابلة.
--   3) الدورات المعنية: فتح status='locked'→'open' + تمديد الموعد 30 يوماً
--      (حتى لا يعيد السجلّ القفل فوراً) + إسقاط use_parallel_flow.
-- المقيّمات النهائية (closed/finalized) لا تُلمس.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- الدورات التي تحتوي مرحلة قديمة — تُجمع قبل أي تعديل.
create temp table _legacy_kpi_cycles on commit drop as
select distinct cycle_id
from public.kpi_evaluations
where current_stage in
  ('parallel_review','secretary_review','executive_review','hr_review','manager_final');

-- ─── 1) تهجير المراحل القديمة non-finalized → manager_review ───────────────
update public.kpi_evaluations
   set stage            = 'manager_review',
       current_stage    = 'manager_review',
       locked           = false,
       workflow_status  = case when workflow_status = 'DRAFT'
                               then workflow_status
                               else 'SUBMITTED_TO_DIRECT_MANAGER' end,
       updated_at       = now()
 where current_stage in
   ('parallel_review','secretary_review','executive_review','hr_review','manager_final');

-- ─── 2) فك قفل بقية المقيّمات non-finalized في الدورات المعنية ─────────────
--        (معكوس ما فعّله process_kpi_cycle_schedule عند الإغلاق التلقائي)
update public.kpi_evaluations e
   set locked          = false,
       workflow_status = case
         when e.workflow_status <> 'OVERDUE' then e.workflow_status
         when e.current_stage = 'self'          then 'OPEN_FOR_SELF_EVALUATION'
         when e.current_stage = 'manager_review' then 'SUBMITTED_TO_DIRECT_MANAGER'
         else e.workflow_status end,
       updated_at      = now()
 where e.locked
   and e.current_stage in ('self','manager_review')
   and e.cycle_id in (select cycle_id from _legacy_kpi_cycles);

-- ─── 3) فتح الدورات المعنية وتمديد ميعادها ─────────────────────────────────
update public.kpi_cycles c
   set status           = case when c.status = 'locked' then 'open' else c.status end,
       extended_until   = case
         when coalesce(c.extended_until, c.deadline_at) < now()
           then now() + interval '30 days'
         else coalesce(c.extended_until, c.deadline_at) end,
       use_parallel_flow = false,
       updated_at       = now()
 where c.id in (select cycle_id from _legacy_kpi_cycles);

-- ─── 4) تسجيل تدقيق (أعداد فقط — بلا PII) ──────────────────────────────────
do $$
declare
  v_cycles int;
  v_evals  int;
begin
  select count(*) into v_cycles from _legacy_kpi_cycles;
  if coalesce(v_cycles, 0) = 0 then
    return;
  end if;
  select count(*) into v_evals
  from public.kpi_evaluations
  where cycle_id in (select cycle_id from _legacy_kpi_cycles);
  perform public.log_audit_event(
    'kpi.legacy_parallel_unstuck', 'workflow', 'notice', 'kpi_cycles', null,
    'إخلاء تقييمات المسار المتوازي القديمة إلى manager_review (0633)',
    null,
    jsonb_build_object('cycles', v_cycles, 'evaluations', v_evals)
  );
end $$;

commit;
