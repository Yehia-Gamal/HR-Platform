-- Migration 0001: Extensions & global conventions
-- Ahla Shabab Management OS V2 — foundation
-- تشغيل عبر: supabase db push  (كل migration immutable — لا تعدّلها بعد التطبيق)

-- ===== Extensions =====
create extension if not exists "pgcrypto";      -- gen_random_uuid(), digest(), crypt()
create extension if not exists "pg_trgm";        -- بحث نصي عربي/lookup
create extension if not exists "citext";         -- بريد/معرّفات case-insensitive

-- ===== helper: server_now (UTC) =====
-- now() يُعيد timestamptz (لحظة زمنية مطلقة) — التخزين والمقارنة صحيحان دون تحويل.
-- تجنّب (now() at time zone 'utc') لأنه يُسقط المنطقة الزمنية ويعيد timestamp ثم يعاد تحويله ضمنياً.
create or replace function public.server_now()
returns timestamptz
language sql stable
as $$ select now() $$;

-- ===== generic trigger: touch updated_at =====
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'Trigger: يحدّث updated_at عند كل UPDATE. يُربط بكل جدول له عمود updated_at.';

-- ملاحظة: كل جدول لاحق يجب أن يحمل:
--   id uuid primary key default gen_random_uuid()
--   created_at timestamptz not null default now()
--   updated_at timestamptz
--   created_by uuid references auth.users(id)
-- ويُفعّل RLS ويربط trigger set_updated_at.
