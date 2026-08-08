-- إعادة تحيل مخزن PostgREST بعد تغييرات get_employee_360
NOTIFY pgrst, 'reload schema';
NOTIFY pgrst;
