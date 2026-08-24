-- =====================================================================
-- 0455: التنبيه الشامل (Broadcast Alert)
-- ---------------------------------------------------------------------
-- زر تنبيهي للمدير التنفيذي ومدير HR: عند الضغط يُرسل تنبيهًا فوريًا
-- لكامل الموظفين — أجهزتهم تُضيء الشاشة وتُشغل الفلاش والاهتزاز.
--
-- المكوّنات:
--   1) صلاحية alerts.broadcast.send تُمنح لـ executive-director وhr-manager
--      بنطاق organization.
--   2) جدول broadcast_alerts: تنبيه واحد نشط في المرة (إرسال جديد يُبطل
--      السابق) مع انتهاء صلاحية تلقائي.
--   3) send_broadcast_alert(p_message): RPC محمي بالصلاحية يبلّغ كل
--      الموظفين النشطين عبر notify_employee (priority = urgent).
--   4) get_active_broadcast_alert(): يستعلمه كل عميل دوريًا لإظهار
--      الطفح الضوئي ما دام هناك تنبيه نشط.
-- =====================================================================

begin;

-- ─── 1) الصلاحية ────────────────────────────────────────────────────────────
insert into public.permissions (code, module, resource, action, description, risk_level, is_sensitive)
values ('alerts.broadcast.send', 'alerts', 'broadcast', 'send',
        'إرسال تنبيه شامل يضيء أجهزة جميع الموظفين', 'sensitive', true)
on conflict (code) do nothing;

insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'organization'
  from public.roles r
 cross join public.permissions p
 where r.slug in ('executive-director', 'hr-manager')
   and p.code = 'alerts.broadcast.send'
on conflict (role_id, permission_id, scope) do nothing;

-- ─── 2) الجدول ──────────────────────────────────────────────────────────────
create table if not exists public.broadcast_alerts (
  id          uuid primary key default gen_random_uuid(),
  message     text not null check (length(trim(message)) between 3 and 300),
  created_by  uuid not null references public.employees(id),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '15 minutes',
  is_active   boolean not null default true
);

comment on table public.broadcast_alerts is 'التنبيهات الشاملة: تنبيه نشط واحد كحد أقصى، ينتهي تلقائيًا بانتهاء expires_at.';

alter table public.broadcast_alerts enable row level security;

drop policy if exists broadcast_alerts_read_authenticated on public.broadcast_alerts;
create policy broadcast_alerts_read_authenticated on public.broadcast_alerts
  for select to authenticated using (true);

create index if not exists ix_broadcast_alerts_active on public.broadcast_alerts (is_active, expires_at desc)
  where is_active;

-- ─── 3) إرسال التنبيه ───────────────────────────────────────────────────────
create or replace function public.send_broadcast_alert(p_message text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_id uuid;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;
  if not public.has_permission('alerts.broadcast.send') then
    raise exception 'broadcast alert permission required' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_message, ''))) < 3
     or length(trim(p_message)) > 300 then
    raise exception 'message must be 3-300 chars' using errcode = '22023';
  end if;

  -- تنبيه نشط واحد فقط في المرة.
  update public.broadcast_alerts set is_active = false where is_active;

  insert into public.broadcast_alerts(message, created_by)
  values (trim(p_message), v_me)
  returning id into v_id;

  perform public.notify_employee(
    e.id,
    'تنبيه عاجل',
    trim(p_message),
    'general',
    'urgent',
    'broadcast_alert',
    v_id,
    jsonb_build_object('alertId', v_id)
  )
    from public.employees e
   where e.is_active = true
     and coalesce(e.is_deleted, false) = false;

  return v_id;
end $$;

revoke execute on function public.send_broadcast_alert(text) from public, anon;
grant execute on function public.send_broadcast_alert(text) to authenticated;

-- ─── 4) استعلام التنبيه النشط ───────────────────────────────────────────────
create or replace function public.get_active_broadcast_alert()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select to_jsonb(x)
    from (
      select a.id, a.message, a.created_at, a.expires_at
        from public.broadcast_alerts a
       where a.is_active = true
         and a.expires_at > now()
       order by a.created_at desc
       limit 1
    ) x;
$$;

revoke execute on function public.get_active_broadcast_alert() from public, anon;
grant execute on function public.get_active_broadcast_alert() to authenticated;

commit;

notify pgrst, 'reload schema';