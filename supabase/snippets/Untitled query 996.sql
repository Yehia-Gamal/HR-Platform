-- استبدل UUID بمعرّف المستخدم من خطوة Authentication
with u as (select 'PASTE-UUID-HERE'::uuid as uid),
     r as (select id from public.roles where slug = 'admin')
-- 1) ملف التعريف (بلا موظف — أول مستخدم إداري)
insert into public.profiles (id, employee_id, primary_role_id, status)
select u.uid, null, r.id, 'active' from u, r
on conflict (id) do update set status = 'active', primary_role_id = excluded.primary_role_id;

-- 2) تعيين الدور (مصدر الحقيقة للصلاحيات)
insert into public.user_roles (user_id, role_id, effective_from, granted_by)
select u.uid, r.id, now(), u.uid from u, r
on conflict do nothing;