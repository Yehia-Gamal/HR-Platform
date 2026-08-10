-- 0365: bridge placeholder — يحافظ على تسلسل أرقام migrations بلا فجوات.
-- لا تغييرات وظيفية هنا؛ وجوده فقط لسدّ الفجوة بين 0364 و0366 حسب
-- سياسة عدم إعادة ترقيم الـ migrations المُطبّقة.
-- (راجع: migrations-zero-renumber-policy في الذاكرة)

select 1;
