begin;

-- Extend the existing notification read model for mobile deep-link routing.
create or replace function public.get_my_notifications(p_limit integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', n.id,
    'title', n.title,
    'body', n.body,
    'category', n.category,
    'priority', n.priority,
    'actionUrl', n.action_url,
    'entityType', n.entity_type,
    'entityId', n.entity_id,
    'isRead', n.is_read,
    'createdAt', n.created_at
  ) order by n.created_at desc), '[]'::jsonb)
  from (
    select * from public.notifications
    where recipient_user_id = auth.uid() and is_archived = false
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  ) n;
$$;
revoke execute on function public.get_my_notifications(integer) from public;
grant execute on function public.get_my_notifications(integer) to authenticated;

commit;
