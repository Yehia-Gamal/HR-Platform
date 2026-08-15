-- 0425: إزالة overload القديم get_attendance_dashboard(date)
-- ══════════════════════════════════════════════════════════════════════
-- نمط 0422/0423/0424: نموذج قديم (p_date date, من 0279) حي في remote رغم
-- استبداله بنموذج حديث بمعاملات DEFAULT (p_date, p_department_id,
-- p_branch_id, p_manager_id — من 0350). استدعاء بمعامل واحد (كما يفعل
-- useAttendanceTrend.ts:73) يطابق كلا النموذجين → "is not unique".
-- النموذج الحديث superset للمكالمات القديمة → الإسقاط بلا تغيير سلوكي.

begin;

drop function if exists public.get_attendance_dashboard(date);

commit;