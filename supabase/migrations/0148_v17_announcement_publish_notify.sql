-- 0146: V17 §9.2.5 — إشعار جماعي عند نشر إعلان رسمي.
-- يُنشئ trigger على جدول announcements يرسل إشعاراً لكل موظف نشط
-- عند نشر إعلان (INSERT بحالة published أو UPDATE من مسودة إلى published).
-- يغطي كلا مساري النشر: publish_announcement و publish_official_announcement.
-- ============================================================================

-- ── 1) دالة الإشعار الجماعي ──

create or replace function public.trg_announcement_broadcast_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- فقط عند الانتقال إلى حالة published
  if new.status <> 'published' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'published' then
    return new;
  end if;

  -- إدراج إشعار لكل موظف نشط لديه حساب مستخدم
  insert into public.notifications(
    recipient_user_id,
    recipient_employee_id,
    title,
    body,
    category,
    priority,
    entity_type,
    entity_id,
    metadata,
    created_by
  )
  select
    p.id,
    e.id,
    'إعلان رسمي جديد',
    left(new.title, 200),
    'announcement',
    coalesce(new.priority, 'normal'),
    'announcement',
    new.id,
    jsonb_build_object(
      'announcement_id', new.id::text,
      'category', coalesce(new.category, 'general')
    ),
    coalesce(new.created_by, '00000000-0000-0000-0000-000000000000'::uuid)
  from public.employees e
  join public.profiles p on p.employee_id = e.id
  where e.is_active = true
    and e.is_deleted = false
    and e.status = 'active'
    and e.user_id is not null;

  return new;
end;
$$;

-- ── 2) ربط الـ trigger ──

drop trigger if exists trg_announcements_broadcast_notify on public.announcements;

create trigger trg_announcements_broadcast_notify
  after insert or update of status on public.announcements
  for each row
  execute function public.trg_announcement_broadcast_notify();

comment on function public.trg_announcement_broadcast_notify() is
  'V17 §9.2.5: إشعار جماعي لكل الموظفين عند نشر إعلان رسمي.';
