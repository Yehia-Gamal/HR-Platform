-- 0358: announcement views/reactions, visible engagement roster, and immediate push nudge.
begin;

create table if not exists public.announcement_views (
  id uuid primary key default gen_random_uuid(),
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  first_viewed_at timestamptz not null default now(),
  last_viewed_at timestamptz not null default now(),
  view_count integer not null default 1 check (view_count > 0),
  created_by uuid references auth.users(id),
  unique (announcement_id, employee_id)
);

create index if not exists ix_announcement_views_announcement_last
  on public.announcement_views(announcement_id, last_viewed_at desc);
alter table public.announcement_views enable row level security;

drop policy if exists announcement_views_select on public.announcement_views;
create policy announcement_views_select on public.announcement_views
  for select to authenticated using (
    employee_id = public.current_employee_id()
    or public.current_is_full_access()
    or public.has_any_permission(array['comms.announcement.manage','posts.publish'])
  );
drop policy if exists announcement_views_insert on public.announcement_views;
create policy announcement_views_insert on public.announcement_views
  for insert to authenticated with check (employee_id = public.current_employee_id());
drop policy if exists announcement_views_update on public.announcement_views;
create policy announcement_views_update on public.announcement_views
  for update to authenticated using (employee_id = public.current_employee_id())
  with check (employee_id = public.current_employee_id());

create table if not exists public.announcement_reactions (
  id uuid primary key default gen_random_uuid(),
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  reaction_type text not null check (reaction_type in ('like','celebrate','support','insightful')),
  reacted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique (announcement_id, employee_id)
);

create index if not exists ix_announcement_reactions_announcement_updated
  on public.announcement_reactions(announcement_id, updated_at desc);
alter table public.announcement_reactions enable row level security;

drop policy if exists announcement_reactions_select on public.announcement_reactions;
create policy announcement_reactions_select on public.announcement_reactions
  for select to authenticated using (
    employee_id = public.current_employee_id()
    or public.current_is_full_access()
    or public.has_any_permission(array['comms.announcement.manage','posts.publish'])
  );
drop policy if exists announcement_reactions_insert on public.announcement_reactions;
create policy announcement_reactions_insert on public.announcement_reactions
  for insert to authenticated with check (employee_id = public.current_employee_id());
drop policy if exists announcement_reactions_update on public.announcement_reactions;
create policy announcement_reactions_update on public.announcement_reactions
  for update to authenticated using (employee_id = public.current_employee_id())
  with check (employee_id = public.current_employee_id());
drop policy if exists announcement_reactions_delete on public.announcement_reactions;
create policy announcement_reactions_delete on public.announcement_reactions
  for delete to authenticated using (employee_id = public.current_employee_id());

create or replace function public.record_announcement_view(p_announcement_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_me uuid:=public.current_employee_id(); v_result jsonb;
begin
  if v_me is null then raise exception 'no employee linked to current user' using errcode='42501'; end if;
  if not exists(select 1 from public.announcements where id=p_announcement_id and status='published') then
    raise exception 'announcement not found or not visible' using errcode='P0002';
  end if;
  insert into public.announcement_views(announcement_id,employee_id,created_by)
  values(p_announcement_id,v_me,auth.uid())
  on conflict(announcement_id,employee_id) do update
    set last_viewed_at=now(),view_count=public.announcement_views.view_count+1;
  select jsonb_build_object(
    'viewCount',(select count(*)::integer from public.announcement_views where announcement_id=p_announcement_id),
    'reactionCount',(select count(*)::integer from public.announcement_reactions where announcement_id=p_announcement_id),
    'myReaction',(select reaction_type from public.announcement_reactions where announcement_id=p_announcement_id and employee_id=v_me)
  ) into v_result;
  return v_result;
end $$;
revoke all on function public.record_announcement_view(uuid) from public,anon;
grant execute on function public.record_announcement_view(uuid) to authenticated;

create or replace function public.toggle_announcement_reaction(p_announcement_id uuid,p_reaction_type text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_me uuid:=public.current_employee_id(); v_existing text; v_actor text;
  v_publisher_user uuid; v_publisher_employee uuid; v_title text; v_active boolean:=true;
begin
  if v_me is null then raise exception 'no employee linked to current user' using errcode='42501'; end if;
  if p_reaction_type not in ('like','celebrate','support','insightful') then
    raise exception 'invalid reaction type' using errcode='22023';
  end if;
  select a.title,a.created_by,p.employee_id into v_title,v_publisher_user,v_publisher_employee
  from public.announcements a left join public.profiles p on p.id=a.created_by and p.status='active'
  where a.id=p_announcement_id and a.status='published';
  if not found then raise exception 'announcement not found or not visible' using errcode='P0002'; end if;

  select reaction_type into v_existing from public.announcement_reactions
  where announcement_id=p_announcement_id and employee_id=v_me for update;
  if v_existing=p_reaction_type then
    delete from public.announcement_reactions where announcement_id=p_announcement_id and employee_id=v_me;
    v_active:=false;
  else
    insert into public.announcement_reactions(announcement_id,employee_id,reaction_type,created_by)
    values(p_announcement_id,v_me,p_reaction_type,auth.uid())
    on conflict(announcement_id,employee_id) do update set reaction_type=excluded.reaction_type,updated_at=now();
    if v_publisher_user is not null and v_publisher_employee is distinct from v_me then
      select full_name_ar into v_actor from public.employees where id=v_me;
      perform public.notify_user(
        v_publisher_user,'تفاعل جديد على إعلانك',
        coalesce(v_actor,'أحد الموظفين')||' تفاعل مع «'||left(v_title,120)||'».',
        'announcement','normal','announcement',p_announcement_id,
        jsonb_build_object('kind','announcement_reaction','reactionType',p_reaction_type,
          'actorEmployeeId',v_me,'announcementId',p_announcement_id));
    end if;
  end if;
  return jsonb_build_object(
    'active',v_active,'myReaction',case when v_active then p_reaction_type else null end,
    'viewCount',(select count(*)::integer from public.announcement_views where announcement_id=p_announcement_id),
    'reactionCount',(select count(*)::integer from public.announcement_reactions where announcement_id=p_announcement_id),
    'reactionSummary',coalesce((select jsonb_object_agg(reaction_type,total) from (
      select reaction_type,count(*)::integer total from public.announcement_reactions
      where announcement_id=p_announcement_id group by reaction_type) s),'{}'::jsonb));
end $$;
revoke all on function public.toggle_announcement_reaction(uuid,text) from public,anon;
grant execute on function public.toggle_announcement_reaction(uuid,text) to authenticated;

create or replace function public.get_announcement_engagement(p_announcement_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not(public.current_is_full_access()
    or public.has_any_permission(array['comms.announcement.manage','posts.publish'])
    or exists(select 1 from public.announcements where id=p_announcement_id and created_by=auth.uid())) then
    raise exception 'not authorized to view announcement engagement' using errcode='42501';
  end if;
  if not exists(select 1 from public.announcements where id=p_announcement_id) then
    raise exception 'announcement not found' using errcode='P0002';
  end if;
  return jsonb_build_object(
    'announcementId',p_announcement_id,
    'targetCount',(select count(*)::integer from public.employees e join public.profiles p on p.employee_id=e.id and p.status='active' where e.is_active and e.status='active' and not e.is_deleted),
    'viewerCount',(select count(*)::integer from public.announcement_views where announcement_id=p_announcement_id),
    'reactionCount',(select count(*)::integer from public.announcement_reactions where announcement_id=p_announcement_id),
    'acknowledgedCount',(select count(*)::integer from public.announcement_acknowledgements where announcement_id=p_announcement_id),
    'viewers',coalesce((select jsonb_agg(jsonb_build_object('employeeId',e.id,'name',e.full_name_ar,'photoUrl',e.photo_url,'at',v.last_viewed_at,'viewCount',v.view_count) order by v.last_viewed_at desc) from public.announcement_views v join public.employees e on e.id=v.employee_id where v.announcement_id=p_announcement_id),'[]'::jsonb),
    'reactions',coalesce((select jsonb_agg(jsonb_build_object('employeeId',e.id,'name',e.full_name_ar,'photoUrl',e.photo_url,'at',r.updated_at,'reactionType',r.reaction_type) order by r.updated_at desc) from public.announcement_reactions r join public.employees e on e.id=r.employee_id where r.announcement_id=p_announcement_id),'[]'::jsonb),
    'acknowledgements',coalesce((select jsonb_agg(jsonb_build_object('employeeId',e.id,'name',e.full_name_ar,'photoUrl',e.photo_url,'at',a.created_at) order by a.created_at desc) from public.announcement_acknowledgements a join public.employees e on e.id=a.employee_id where a.announcement_id=p_announcement_id),'[]'::jsonb));
end $$;
revoke all on function public.get_announcement_engagement(uuid) from public,anon;
grant execute on function public.get_announcement_engagement(uuid) to authenticated;

create or replace function public.get_official_feed_admin(p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
select coalesce(jsonb_agg(item order by sort_at desc),'[]'::jsonb) from (
  select item,sort_at from (
    select jsonb_build_object(
      'id',a.id,'kind','announcement','title',a.title,'body',a.body,'category',a.category,
      'priority',a.priority,'status',a.status,'postType',coalesce(a.post_type,'announcement'),
      'requiresAcknowledgement',a.requires_acknowledgement,'publishedAt',a.published_at,'expiresAt',a.expires_at,
      'imageUrl',a.banner_url,'authorName',ea.full_name_ar,'authorPhotoUrl',ea.photo_url,
      'acknowledgedCount',(select count(*)::integer from public.announcement_acknowledgements x where x.announcement_id=a.id),
      'viewCount',(select count(*)::integer from public.announcement_views x where x.announcement_id=a.id),
      'reactionCount',(select count(*)::integer from public.announcement_reactions x where x.announcement_id=a.id),
      'reactionSummary',coalesce((select jsonb_object_agg(reaction_type,total) from (select reaction_type,count(*)::integer total from public.announcement_reactions where announcement_id=a.id group by reaction_type)s),'{}'::jsonb),
      'targetCount',(select count(*)::integer from public.employees te join public.profiles tp on tp.employee_id=te.id and tp.status='active' where te.is_active and te.status='active' and not te.is_deleted),
      'myAcknowledged',exists(select 1 from public.announcement_acknowledgements x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'myReaction',(select reaction_type from public.announcement_reactions x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'createdAt',a.created_at) item,coalesce(a.published_at,a.created_at) sort_at
    from public.announcements a left join public.employees ea on ea.user_id=a.created_by
    union all
    select jsonb_build_object(
      'id',d.id,'kind','decision','title',d.title,'body',coalesce(d.body,''),'category',d.category,
      'priority',coalesce(d.metadata->>'priority','high'),'status',d.status,'postType','decision',
      'requiresAcknowledgement',d.requires_read_receipt,'publishedAt',d.published_at,'expiresAt',d.expiry_date,
      'imageUrl',d.attachment_url,'authorName',coalesce(ed2.full_name_ar,ed1.full_name_ar),'authorPhotoUrl',coalesce(ed2.photo_url,ed1.photo_url),
      'acknowledgedCount',(select count(*)::integer from public.decision_reads x where x.decision_id=d.id and x.acknowledged),
      'viewCount',(select count(*)::integer from public.decision_reads x where x.decision_id=d.id),
      'reactionCount',0,'reactionSummary','{}'::jsonb,
      'targetCount',(select count(*)::integer from public.decision_recipients x where x.decision_id=d.id),
      'myAcknowledged',exists(select 1 from public.decision_reads x where x.decision_id=d.id and x.employee_id=public.current_employee_id() and x.acknowledged),
      'myReaction',null,'createdAt',d.created_at) item,coalesce(d.published_at,d.created_at) sort_at
    from public.administrative_decisions d left join public.employees ed1 on ed1.user_id=d.created_by left join public.employees ed2 on ed2.id=d.issued_by
  ) u order by sort_at desc limit greatest(1,least(coalesce(p_limit,100),500))
) feed $$;
grant execute on function public.get_official_feed_admin(integer) to authenticated;

create or replace function public.get_mobile_feed_item(p_kind text,p_item_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
  if lower(p_kind)='announcement' then
    select jsonb_build_object('id',a.id,'kind','announcement','title',a.title,'body',a.body,
      'category',a.category,'priority',a.priority,'status',a.status,'postType',coalesce(a.post_type,'announcement'),
      'requiresAcknowledgement',a.requires_acknowledgement,
      'myAcknowledged',exists(select 1 from public.announcement_acknowledgements x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'myReaction',(select reaction_type from public.announcement_reactions x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'viewCount',(select count(*)::integer from public.announcement_views x where x.announcement_id=a.id),
      'reactionCount',(select count(*)::integer from public.announcement_reactions x where x.announcement_id=a.id),
      'reactionSummary',coalesce((select jsonb_object_agg(reaction_type,total) from (select reaction_type,count(*)::integer total from public.announcement_reactions where announcement_id=a.id group by reaction_type)s),'{}'::jsonb),
      'publishedAt',a.published_at,'expiresAt',a.expires_at,'imageUrl',a.banner_url,
      'authorName',e.full_name_ar,'authorPhotoUrl',e.photo_url,
      'attachments',case when a.banner_url is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('url',a.banner_url,'type','banner')) end)
    into v_result from public.announcements a left join public.employees e on e.user_id=a.created_by where a.id=p_item_id and a.status='published';
  elsif lower(p_kind)='decision' then
    select jsonb_build_object('id',d.id,'kind','decision','title',d.title,'body',coalesce(d.body,''),
      'category',d.category,'priority',coalesce(d.metadata->>'priority','high'),'status',d.status,'postType','decision',
      'requiresAcknowledgement',d.requires_read_receipt,
      'myAcknowledged',exists(select 1 from public.decision_reads x where x.decision_id=d.id and x.employee_id=public.current_employee_id() and x.acknowledged),
      'myReaction',null,'viewCount',(select count(*)::integer from public.decision_reads x where x.decision_id=d.id),
      'reactionCount',0,'reactionSummary','{}'::jsonb,'publishedAt',d.published_at,'expiresAt',d.expiry_date,
      'imageUrl',d.attachment_url,'decisionNumber',d.decision_number,'effectiveDate',d.effective_date,
      'attachments',case when d.attachment_url is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('url',d.attachment_url,'type','attachment')) end)
    into v_result from public.administrative_decisions d where d.id=p_item_id and d.status='published';
  elsif lower(p_kind)='recognition' then
    select jsonb_build_object('id',r.id,'kind','recognition','title',r.title,'body',coalesce(r.message,''),
      'category',r.recognition_type,'priority',coalesce(r.metadata->>'priority','normal'),'status','published',
      'requiresAcknowledgement',false,'myAcknowledged',false,'myReaction',null,'viewCount',0,'reactionCount',0,
      'reactionSummary','{}'::jsonb,'publishedAt',r.awarded_at,'expiresAt',null,'imageUrl',null,'postType','recognition',
      'authorName',coalesce(nom.full_name_ar,'الإدارة'),'authorPhotoUrl',null,'attachments','[]'::jsonb)
    into v_result from public.recognitions r left join public.employees nom on nom.id=r.nominated_by
    where r.id=p_item_id and (r.is_public or r.recipient_employee_id=public.current_employee_id() or r.nominated_by=public.current_employee_id()
      or public.current_is_full_access() or public.has_any_permission(array['recognition.read','recognition.manage']));
  else raise exception 'unsupported feed item kind' using errcode='22023'; end if;
  if v_result is null then raise exception 'feed item not found or not visible' using errcode='P0002'; end if;
  return v_result;
end $$;
revoke all on function public.get_mobile_feed_item(text,uuid) from public,anon;
grant execute on function public.get_mobile_feed_item(text,uuid) to authenticated;

-- A later decide_request definition stopped notifying the next approver. A small
-- transition trigger restores that event without copying the large workflow RPC.
create or replace function public.trg_request_step_activated_notify()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_req public.requests;
begin
  if new.status<>'active' or old.status='active' or new.assignee_employee_id is null then return new; end if;
  select * into v_req from public.requests where id=new.request_id;
  if v_req.id is null or new.assignee_employee_id=v_req.employee_id then return new; end if;
  if not exists(select 1 from public.notifications where recipient_employee_id=new.assignee_employee_id
    and entity_type='request' and entity_id=new.request_id and metadata->>'eventKey'='step-active:'||new.id::text) then
    perform public.notify_employee(new.assignee_employee_id,'طلب بانتظار مراجعتك',
      format('%s — %s',public.request_type_label(v_req.request_type),coalesce(v_req.title,'')),
      'request','normal','request',v_req.id,jsonb_build_object('kind','request_approval_needed',
      'eventKey','step-active:'||new.id::text,'requestType',v_req.request_type,'stepOrder',new.step_order));
  end if;
  return new;
end $$;
drop trigger if exists trg_request_step_activated_notify on public.request_steps;
create trigger trg_request_step_activated_notify after update of status on public.request_steps
for each row execute function public.trg_request_step_activated_notify();

-- Casual leave is auto-approved by submit_my_request and bypasses decide_request.
create or replace function public.trg_casual_leave_auto_approved_notify()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if old.status=new.status or new.status<>'approved' or new.request_type<>'leave'
    or coalesce(new.payload->>'leaveType','')<>'casual' or new.decided_by is distinct from new.employee_id then return new; end if;
  perform public.notify_employee(new.employee_id,'تم اعتماد إجازتك العارضة',
    coalesce(new.title,'تم تسجيل الإجازة العارضة وتنفيذها مباشرة.'),'request','normal','request',new.id,
    jsonb_build_object('kind','casual_leave_auto_approved','decision','approve','requestType','leave'));
  return new;
end $$;
drop trigger if exists trg_casual_leave_auto_approved_notify on public.requests;
create trigger trg_casual_leave_auto_approved_notify after update of status on public.requests
for each row execute function public.trg_casual_leave_auto_approved_notify();

-- Wake the dispatcher once per transaction. pg_net sends after commit; cron stays fallback.
create or replace function public.trg_notifications_nudge_dispatcher()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if coalesce(current_setting('app.notifications_dispatcher_nudged',true),'')<>'1' then
    perform set_config('app.notifications_dispatcher_nudged','1',true);
    perform public.nudge_notification_dispatcher();
  end if;
  return null;
end $$;
drop trigger if exists trg_notifications_nudge_dispatcher on public.notifications;
create trigger trg_notifications_nudge_dispatcher after insert on public.notifications
for each statement execute function public.trg_notifications_nudge_dispatcher();

notify pgrst,'reload schema';
commit;
