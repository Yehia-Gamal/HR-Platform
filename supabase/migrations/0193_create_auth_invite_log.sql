-- Migration 0193: إنشاء جدول auth_invite_log
-- المشكلة: Edge Function admin-resend-invite تعتمد على جدول auth_invite_log
-- لتحديد معدل إعادة الدعوات (rate-limit)، لكن الجدول غير موجود.
-- النتيجة: catch block يبتلع الخطأ بصمت ← rate-limit لا يعمل أبداً.

begin;

create table if not exists public.auth_invite_log (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  sent_by     uuid not null references auth.users(id) on delete set null,
  email       text not null,
  created_at  timestamptz not null default now()
);

comment on table public.auth_invite_log is
  'سجل إعادة إرسال دعوات التفعيل — يُستخدم لتحديد المعدل (مرة كل 60 ثانية لكل موظف).';

-- فهرس للبحث السريع عند فحص rate-limit
create index if not exists idx_auth_invite_log_employee_created
  on public.auth_invite_log(employee_id, created_at desc);

-- RLS: فقط service_role يكتب/يقرأ (عبر Edge Function)
alter table public.auth_invite_log enable row level security;

-- لا توجد سياسات RLS = لا أحد يصل عبر anon/authenticated مباشرة.
-- Edge Function تستخدم service_role client الذي يتجاوز RLS.

-- منح الصلاحيات الأساسية للـ service_role
grant select, insert on public.auth_invite_log to service_role;

commit;
