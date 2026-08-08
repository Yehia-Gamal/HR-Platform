-- إعادة تحميل مخزن PostgREST مرة أخيرة لضمان التقاط آخر تغييرات الدوال
NOTIFY pgrst, 'reload schema';
