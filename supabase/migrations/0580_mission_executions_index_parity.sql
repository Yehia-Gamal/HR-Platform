-- 0580: استعادة فهارس mission_executions المفقودة في القواعد الجديدة.
-- 0318 تنشئ mission_executions_employee_idx، ثم 0558 تحذفها افتراضاً وجود
-- ix_mission_executions_employee (موجودة في prod يدوياً) — فتبقى قواعد CI/التطوير
-- بلا أي فهرس على employee_id، ويكسر اختبار 0558 («الفهرس المتبقي موجود»).
create index if not exists ix_mission_executions_employee
  on public.mission_executions (employee_id);

-- بديل الفهرس المunique على request_id الموجود في prod (الجديد يكتفي بـ pkey).
create index if not exists ix_mission_executions_request
  on public.mission_executions (request_id);
