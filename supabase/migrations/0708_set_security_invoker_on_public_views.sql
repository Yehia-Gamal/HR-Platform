-- 0708: تفعيل security_invoker على العروض العامة لمنع تجاوز RLS
-- يغلق الثغرة الأمنية على عروض attendance_roster و official_holidays

begin;

alter view public.official_holidays set (security_invoker = true);
alter view public.attendance_roster set (security_invoker = true);

commit;
