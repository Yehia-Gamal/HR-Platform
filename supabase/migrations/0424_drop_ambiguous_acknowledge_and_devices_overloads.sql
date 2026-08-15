-- 0424: إزالة overloads الغامضة acknowledge_decision(uuid) وget_all_devices_admin(text)
-- ══════════════════════════════════════════════════════════════════════
-- نمط 0422/0423: كل دالة لها نموذج قديم ونموذج حديث بمعاملات DEFAULT،
-- فاستدعاء بعدد معاملات أصغر يطابق كلا النموذجين → Postgres يرفض بـ
-- "is not unique". تأكيد بالاختبار المباشر:
--   * acknowledge_decision(uuid)                      → not unique
--   * get_all_devices_admin('active')                 → not unique
-- النموذجان المتبقيان (بـ defaults) هما superset لكامل المكالمات القديمة:
--   * acknowledge_decision(uuid, boolean)  — p_acknowledge DEFAULT true
--   * get_all_devices_admin(text, boolean) — p_include_terminated DEFAULT false
-- لذا الإسقاط بلا أي تغيير سلوكي.

begin;

drop function if exists public.acknowledge_decision(uuid);
drop function if exists public.get_all_devices_admin(text);

commit;