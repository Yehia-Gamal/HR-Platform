begin;

-- Migration 0498: السماح بـ source='mission_auto' في attendance_events.
-- 0481 (end_my_mission) يُنشئ عند الإنهاء قبل نهاية الدوام حدث CHECK_IN تلقائياً
--   بـ source='mission_auto' (auto_check_in_from_mission_end) حتى يمر تسلسل
--   record_attendance_local_biometric. لكن قيد attendance_events_source_check
--   (منذ 0005) كان يقبل فقط ('mobile','web','kiosk','service','import') — فأي
--   إنهاء مأمورية قبل نهاية الدوام كان يفشل بـ 23514. هذا الإصلاح يضيف
--   'mission_auto' للقيم المسموحة، مع الحفاظ على بقية القيم.

alter table public.attendance_events
  drop constraint if exists attendance_events_source_check;

alter table public.attendance_events
  add constraint attendance_events_source_check
  check (source in ('mobile','web','kiosk','service','import','mission_auto'));

comment on constraint attendance_events_source_check on public.attendance_events is
  '0498: مصادر أحداث الحضور — أُضيف mission_auto (حدث CHECK_IN التلقائي عند إنهاء مأمورية قبل نهاية الدوام — 0481).';

commit;
