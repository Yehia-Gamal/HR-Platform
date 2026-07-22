-- Migration 0031: controlled employee documents, asset custody and offboarding lifecycle
begin;

insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive)
values
 ('documents.employee.manage','documents','employee_document','manage','إدارة مستندات الموظفين','sensitive',true),
 ('documents.employee.verify','documents','employee_document','verify','التحقق من مستندات الموظف','sensitive',true),
 ('assets.inventory.manage','assets','inventory','manage','إدارة مخزون العهد','sensitive',true),
 ('assets.assignment.manage','assets','assignment','manage','تسليم واستلام العهد','sensitive',true),
 ('offboarding.case.manage','offboarding','case','manage','إدارة إنهاء الخدمة وإخلاء الطرف','critical',true),
 ('offboarding.case.approve','offboarding','case','approve','اعتماد الإنهاء النهائي','critical',true)
on conflict(code) do nothing;

alter table public.employee_documents
 add column if not exists status text not null default 'active' check(status in ('active','expired','rejected','archived')),
 add column if not exists verified_at timestamptz,
 add column if not exists verified_by uuid references public.employees(id) on delete set null,
 add column if not exists rejection_reason text,
 add column if not exists file_hash text,
 add column if not exists mime_type text,
 add column if not exists size_bytes bigint check(size_bytes is null or size_bytes>=0);

alter table public.asset_inventory
 add column if not exists asset_code text,
 add column if not exists purchase_date date,
 add column if not exists purchase_cost numeric(14,2),
 add column if not exists current_location text,
 add column if not exists notes text;
create unique index if not exists ux_asset_inventory_code on public.asset_inventory(asset_code) where asset_code is not null;

alter table public.asset_assignments
 add column if not exists status text not null default 'assigned' check(status in ('assigned','return_requested','returned','lost','damaged','written_off')),
 add column if not exists handed_over_by uuid references public.employees(id) on delete set null,
 add column if not exists return_received_by uuid references public.employees(id) on delete set null,
 add column if not exists return_sig_path text,
 add column if not exists notes text;

create table if not exists public.document_access_logs (
 id uuid primary key default gen_random_uuid(),
 employee_document_id uuid not null references public.employee_documents(id) on delete cascade,
 action text not null check(action in ('view','download','verify','reject','archive')),
 actor_user_id uuid references auth.users(id),
 actor_employee_id uuid references public.employees(id) on delete set null,
 reason text,
 created_at timestamptz not null default now(),
 metadata jsonb not null default '{}'::jsonb
);

create table if not exists public.offboarding_cases (
 id uuid primary key default gen_random_uuid(),
 employee_id uuid not null references public.employees(id) on delete restrict,
 case_number text not null unique,
 reason_type text not null check(reason_type in ('resignation','termination','contract_end','retirement','probation_failed','other')),
 reason text,
 notice_date date,
 last_working_date date not null,
 status text not null default 'draft' check(status in ('draft','submitted','in_clearance','ready_for_approval','approved','completed','cancelled')),
 handover_employee_id uuid references public.employees(id) on delete set null,
 exit_interview_notes text,
 final_settlement_reference text,
 approved_by uuid references public.employees(id) on delete set null,
 approved_at timestamptz,
 completed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz,
 created_by uuid references auth.users(id),
 check(notice_date is null or last_working_date>=notice_date)
);

create table if not exists public.offboarding_clearance_items (
 id uuid primary key default gen_random_uuid(),
 offboarding_case_id uuid not null references public.offboarding_cases(id) on delete cascade,
 category text not null check(category in ('manager','hr','it','finance','assets','documents','access','knowledge_transfer','other')),
 title text not null,
 owner_role text,
 assignee_employee_id uuid references public.employees(id) on delete set null,
 status text not null default 'pending' check(status in ('pending','in_progress','completed','waived','blocked')),
 due_at timestamptz,
 evidence_path text,
 completion_note text,
 completed_at timestamptz,
 completed_by uuid references public.employees(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz,
 created_by uuid references auth.users(id)
);

create table if not exists public.knowledge_transfer_items (
 id uuid primary key default gen_random_uuid(),
 offboarding_case_id uuid not null references public.offboarding_cases(id) on delete cascade,
 title text not null,
 description text,
 destination_employee_id uuid references public.employees(id) on delete set null,
 document_path text,
 status text not null default 'pending' check(status in ('pending','shared','acknowledged')),
 acknowledged_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz,
 created_by uuid references auth.users(id)
);

create table if not exists public.offboarding_actions (
 id uuid primary key default gen_random_uuid(),
 offboarding_case_id uuid not null references public.offboarding_cases(id) on delete cascade,
 action_type text not null,
 from_status text,
 to_status text,
 note text,
 actor_employee_id uuid references public.employees(id) on delete set null,
 actor_user_id uuid references auth.users(id),
 created_at timestamptz not null default now(),
 metadata jsonb not null default '{}'::jsonb
);

create index if not exists ix_employee_documents_expiry on public.employee_documents(expiry,status);
create index if not exists ix_asset_assignments_employee_status on public.asset_assignments(employee_id,status);
create index if not exists ix_offboarding_cases_status on public.offboarding_cases(status,last_working_date);
create index if not exists ix_clearance_case_status on public.offboarding_clearance_items(offboarding_case_id,status);

do $$ declare t text; begin
 foreach t in array array['offboarding_cases','offboarding_clearance_items','knowledge_transfer_items'] loop
  execute format('drop trigger if exists trg_%1$s_updated_at on public.%1$s',t);
  execute format('create trigger trg_%1$s_updated_at before update on public.%1$s for each row execute function public.tg_set_updated_at()',t);
 end loop;
 foreach t in array array['document_access_logs','offboarding_cases','offboarding_clearance_items','knowledge_transfer_items','offboarding_actions'] loop execute format('alter table public.%I enable row level security',t); end loop;
end $$;

-- Replace broad direct document/asset writes with controlled RPCs.
drop policy if exists employee_documents_insert on public.employee_documents;
drop policy if exists employee_documents_update on public.employee_documents;
drop policy if exists employee_documents_delete on public.employee_documents;
revoke insert,update,delete on public.employee_documents from authenticated;

drop policy if exists asset_inventory_write on public.asset_inventory;
drop policy if exists asset_assignments_write on public.asset_assignments;
revoke insert,update,delete on public.asset_inventory,public.asset_assignments from authenticated;

drop policy if exists offboarding_cases_read on public.offboarding_cases;
create policy offboarding_cases_read on public.offboarding_cases for select to authenticated using(
 employee_id=public.current_employee_id() or handover_employee_id=public.current_employee_id() or public.current_is_full_access() or public.has_permission('offboarding.case.manage')
);
create policy clearance_items_read on public.offboarding_clearance_items for select to authenticated using(
 assignee_employee_id=public.current_employee_id() or exists(select 1 from public.offboarding_cases c where c.id=offboarding_case_id and (c.employee_id=public.current_employee_id() or c.handover_employee_id=public.current_employee_id())) or public.current_is_full_access() or public.has_permission('offboarding.case.manage')
);
create policy knowledge_transfer_read on public.knowledge_transfer_items for select to authenticated using(
 destination_employee_id=public.current_employee_id() or exists(select 1 from public.offboarding_cases c where c.id=offboarding_case_id and c.employee_id=public.current_employee_id()) or public.current_is_full_access() or public.has_permission('offboarding.case.manage')
);
create policy offboarding_actions_read on public.offboarding_actions for select to authenticated using(
 exists(select 1 from public.offboarding_cases c where c.id=offboarding_case_id and (c.employee_id=public.current_employee_id() or c.handover_employee_id=public.current_employee_id())) or public.current_is_full_access() or public.has_permission('offboarding.case.manage')
);
create policy document_access_logs_read on public.document_access_logs for select to authenticated using(public.current_is_full_access() or public.has_permission('documents.employee.manage'));
revoke insert,update,delete on public.document_access_logs,public.offboarding_cases,public.offboarding_clearance_items,public.knowledge_transfer_items,public.offboarding_actions from authenticated;

create or replace function public.register_employee_document_admin(p_employee_id uuid,p_doc_type text,p_title text,p_storage_path text,p_doc_number text default null,p_issue_date date default null,p_expiry date default null,p_file_hash text default null,p_mime_type text default null,p_size_bytes bigint default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if not(public.current_is_full_access() or public.can_access_employee(p_employee_id,'documents.employee.manage')) then raise exception 'FORBIDDEN'; end if;
 if length(trim(p_doc_type))<2 or length(trim(p_title))<2 or length(trim(p_storage_path))<3 then raise exception 'INVALID_DOCUMENT'; end if;
 insert into public.employee_documents(employee_id,doc_type,title,doc_number,issue_date,expiry,storage_path,file_hash,mime_type,size_bytes,is_verified,status,created_by)
 values(p_employee_id,trim(p_doc_type),trim(p_title),p_doc_number,p_issue_date,p_expiry,trim(p_storage_path),p_file_hash,p_mime_type,p_size_bytes,false,'active',auth.uid()) returning id into v_id;
 perform public.log_audit_event('documents.employee.registered','data','notice','employee_documents',v_id,'تسجيل مستند موظف',null,jsonb_build_object('employeeId',p_employee_id,'docType',p_doc_type)); return v_id;
end $$;

create or replace function public.review_employee_document(p_document_id uuid,p_decision text,p_reason text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.employee_documents;
begin
 select * into strict v from public.employee_documents where id=p_document_id for update;
 if not(public.current_is_full_access() or public.can_access_employee(v.employee_id,'documents.employee.verify')) then raise exception 'FORBIDDEN'; end if;
 if p_decision not in ('verified','rejected','archived') then raise exception 'INVALID_DECISION'; end if;
 if p_decision='rejected' and length(trim(coalesce(p_reason,'')))<5 then raise exception 'REASON_REQUIRED'; end if;
 update public.employee_documents set is_verified=p_decision='verified',verified_at=case when p_decision='verified' then now() end,verified_by=case when p_decision='verified' then public.current_employee_id() end,status=case p_decision when 'verified' then 'active' else p_decision end,rejection_reason=case when p_decision='rejected' then trim(p_reason) end,updated_at=now() where id=p_document_id;
 insert into public.document_access_logs(employee_document_id,action,actor_user_id,actor_employee_id,reason) values(p_document_id,case p_decision when 'verified' then 'verify' when 'rejected' then 'reject' else 'archive' end,auth.uid(),public.current_employee_id(),p_reason);
end $$;

create or replace function public.save_asset_admin(p_asset_id uuid,p_asset_code text,p_asset_type text,p_name text,p_serial text default null,p_condition text default null,p_location text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if not(public.current_is_full_access() or public.has_permission('assets.inventory.manage')) then raise exception 'FORBIDDEN'; end if;
 if p_asset_id is null then insert into public.asset_inventory(asset_code,asset_type,name_ar,serial,status,condition,current_location,notes,created_by) values(nullif(trim(p_asset_code),''),trim(p_asset_type),trim(p_name),nullif(trim(coalesce(p_serial,'')),''),'available',p_condition,p_location,p_notes,auth.uid()) returning id into v_id;
 else update public.asset_inventory set asset_code=nullif(trim(p_asset_code),''),asset_type=trim(p_asset_type),name_ar=trim(p_name),serial=nullif(trim(coalesce(p_serial,'')),''),condition=p_condition,current_location=p_location,notes=p_notes,updated_at=now() where id=p_asset_id returning id into v_id; end if;
 return v_id;
end $$;

create or replace function public.assign_asset_admin(p_asset_id uuid,p_employee_id uuid,p_condition text default null,p_receipt_path text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_status text;
begin
 if not(public.current_is_full_access() or public.has_permission('assets.assignment.manage')) then raise exception 'FORBIDDEN'; end if;
 select status into strict v_status from public.asset_inventory where id=p_asset_id for update; if v_status<>'available' then raise exception 'ASSET_NOT_AVAILABLE'; end if;
 if not exists(select 1 from public.employees where id=p_employee_id and is_active and not is_deleted) then raise exception 'EMPLOYEE_NOT_ACTIVE'; end if;
 insert into public.asset_assignments(asset_id,employee_id,handed_over_at,receipt_sig_path,status,handed_over_by,notes,created_by) values(p_asset_id,p_employee_id,now(),p_receipt_path,'assigned',public.current_employee_id(),p_notes,auth.uid()) returning id into v_id;
 update public.asset_inventory set status='assigned',condition=coalesce(p_condition,condition),updated_at=now() where id=p_asset_id; return v_id;
end $$;

create or replace function public.return_asset_admin(p_assignment_id uuid,p_condition text,p_return_sig_path text default null,p_notes text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.asset_assignments;
begin
 if not(public.current_is_full_access() or public.has_permission('assets.assignment.manage')) then raise exception 'FORBIDDEN'; end if;
 select * into strict v from public.asset_assignments where id=p_assignment_id for update; if v.status not in ('assigned','return_requested') then raise exception 'INVALID_STATE'; end if;
 update public.asset_assignments set status='returned',returned_at=now(),return_condition=p_condition,return_received_by=public.current_employee_id(),return_sig_path=p_return_sig_path,notes=coalesce(p_notes,notes),updated_at=now() where id=p_assignment_id;
 update public.asset_inventory set status='available',condition=p_condition,updated_at=now() where id=v.asset_id;
end $$;

create or replace function public.start_offboarding_case(p_employee_id uuid,p_reason_type text,p_reason text,p_notice_date date,p_last_working_date date,p_handover_employee_id uuid default null,p_clearance_items jsonb default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_number text; v_item jsonb;
begin
 if not(public.current_is_full_access() or public.has_permission('offboarding.case.manage')) then raise exception 'FORBIDDEN'; end if;
 if p_employee_id=public.current_employee_id() or p_last_working_date<coalesce(p_notice_date,p_last_working_date) then raise exception 'INVALID_OFFBOARDING'; end if;
 if exists(select 1 from public.offboarding_cases where employee_id=p_employee_id and status not in ('completed','cancelled')) then raise exception 'ACTIVE_OFFBOARDING_EXISTS'; end if;
 v_number:='OFF-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.offboarding_cases(employee_id,case_number,reason_type,reason,notice_date,last_working_date,status,handover_employee_id,created_by)
 values(p_employee_id,v_number,p_reason_type,p_reason,p_notice_date,p_last_working_date,'in_clearance',p_handover_employee_id,auth.uid()) returning id into v_id;
 update public.employees set status='notice_period',is_active=true,updated_at=now() where id=p_employee_id;
 if p_clearance_items is null then p_clearance_items:='[{"category":"manager","title":"تسليم المهام والمعرفة"},{"category":"assets","title":"إعادة جميع العهد"},{"category":"it","title":"إلغاء الوصول التقني"},{"category":"hr","title":"مراجعة الملف والمستندات"},{"category":"finance","title":"التسوية المالية النهائية"}]'::jsonb; end if;
 for v_item in select * from jsonb_array_elements(p_clearance_items) loop
  insert into public.offboarding_clearance_items(offboarding_case_id,category,title,owner_role,due_at,created_by) values(v_id,v_item->>'category',v_item->>'title',v_item->>'ownerRole',p_last_working_date::timestamptz,auth.uid());
 end loop;
 insert into public.offboarding_actions(offboarding_case_id,action_type,to_status,note,actor_employee_id,actor_user_id) values(v_id,'start','in_clearance',p_reason,public.current_employee_id(),auth.uid()); return v_id;
end $$;

create or replace function public.transition_offboarding_clearance_item(p_item_id uuid,p_status text,p_note text default null,p_evidence_path text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.offboarding_clearance_items; v_case public.offboarding_cases;
begin
 select * into strict v from public.offboarding_clearance_items where id=p_item_id for update; select * into strict v_case from public.offboarding_cases where id=v.offboarding_case_id for update;
 if not(public.current_is_full_access() or public.has_permission('offboarding.case.manage') or v.assignee_employee_id=public.current_employee_id()) then raise exception 'FORBIDDEN'; end if;
 if p_status not in ('in_progress','completed','waived','blocked') then raise exception 'INVALID_STATUS'; end if;
 if p_status in ('waived','blocked') and length(trim(coalesce(p_note,'')))<5 then raise exception 'NOTE_REQUIRED'; end if;
 update public.offboarding_clearance_items set status=p_status,completion_note=p_note,evidence_path=p_evidence_path,completed_at=case when p_status in ('completed','waived') then now() end,completed_by=case when p_status in ('completed','waived') then public.current_employee_id() end,updated_at=now() where id=p_item_id;
 if not exists(select 1 from public.offboarding_clearance_items where offboarding_case_id=v.offboarding_case_id and status not in ('completed','waived')) then update public.offboarding_cases set status='ready_for_approval',updated_at=now() where id=v.offboarding_case_id; end if;
end $$;

create or replace function public.approve_offboarding_case(p_case_id uuid,p_final_settlement_reference text default null,p_exit_interview_notes text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.offboarding_cases;
begin
 if not(public.current_is_full_access() or public.has_permission('offboarding.case.approve')) then raise exception 'FORBIDDEN'; end if;
 select * into strict v from public.offboarding_cases where id=p_case_id for update;
 if v.status<>'ready_for_approval' or exists(select 1 from public.asset_assignments where employee_id=v.employee_id and status in ('assigned','return_requested')) then raise exception 'CLEARANCE_OR_ASSETS_PENDING'; end if;
 update public.offboarding_cases set status='completed',approved_by=public.current_employee_id(),approved_at=now(),completed_at=now(),final_settlement_reference=p_final_settlement_reference,exit_interview_notes=p_exit_interview_notes,updated_at=now() where id=p_case_id;
 update public.employees set status='terminated',is_active=false,updated_at=now() where id=v.employee_id;
 update public.profiles set status='disabled',updated_at=now() where employee_id=v.employee_id;
 update public.user_roles set effective_to=coalesce(effective_to,now()) where user_id=(select user_id from public.employees where id=v.employee_id) and (effective_to is null or effective_to>now());
 insert into public.offboarding_actions(offboarding_case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id) values(p_case_id,'approve','ready_for_approval','completed',public.current_employee_id(),auth.uid());
 perform public.log_audit_event('offboarding.completed','workflow','warning','offboarding_cases',p_case_id,'اكتمال إنهاء خدمة موظف',null,jsonb_build_object('employeeId',v.employee_id));
end $$;

create or replace function public.get_documents_assets_offboarding_catalog(p_employee_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['documents.employee.manage','assets.inventory.manage','assets.assignment.manage','offboarding.case.manage']) or (p_employee_id=public.current_employee_id())) then raise exception 'FORBIDDEN'; end if;
 return jsonb_build_object(
 'documents',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'employeeId',d.employee_id,'employeeName',e.full_name_ar,'employeeCode',e.employee_code,'type',d.doc_type,'title',d.title,'number',d.doc_number,'issueDate',d.issue_date,'expiryDate',d.expiry,'status',d.status,'verified',d.is_verified,'storagePath',d.storage_path,'createdAt',d.created_at) order by d.expiry nulls last) from public.employee_documents d join public.employees e on e.id=d.employee_id where p_employee_id is null or d.employee_id=p_employee_id),'[]'::jsonb),
 'assets',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'assetCode',a.asset_code,'type',a.asset_type,'name',a.name_ar,'serial',a.serial,'status',a.status,'condition',a.condition,'location',a.current_location,'assignment',(select jsonb_build_object('id',x.id,'employeeId',x.employee_id,'employeeName',e.full_name_ar,'status',x.status,'handedOverAt',x.handed_over_at,'returnedAt',x.returned_at) from public.asset_assignments x join public.employees e on e.id=x.employee_id where x.asset_id=a.id and x.status in ('assigned','return_requested') order by x.created_at desc limit 1)) order by a.name_ar) from public.asset_inventory a),'[]'::jsonb),
 'offboarding',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'caseNumber',o.case_number,'employeeId',o.employee_id,'employeeName',e.full_name_ar,'employeeCode',e.employee_code,'reasonType',o.reason_type,'lastWorkingDate',o.last_working_date,'status',o.status,'handoverEmployeeId',o.handover_employee_id,'clearance',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'category',c.category,'title',c.title,'status',c.status,'assigneeId',c.assignee_employee_id,'dueAt',c.due_at,'completionNote',c.completion_note) order by c.created_at) from public.offboarding_clearance_items c where c.offboarding_case_id=o.id),'[]'::jsonb)) order by o.created_at desc) from public.offboarding_cases o join public.employees e on e.id=o.employee_id where p_employee_id is null or o.employee_id=p_employee_id),'[]'::jsonb),
 'expiringDocuments',(select count(*) from public.employee_documents where status='active' and expiry between current_date and current_date+30),
 'assignedAssets',(select count(*) from public.asset_assignments where status='assigned'),
 'openOffboarding',(select count(*) from public.offboarding_cases where status not in ('completed','cancelled')),
 'lastUpdatedAt',now());
end $$;

revoke execute on function public.register_employee_document_admin(uuid,text,text,text,text,date,date,text,text,bigint) from public; grant execute on function public.register_employee_document_admin(uuid,text,text,text,text,date,date,text,text,bigint) to authenticated;
revoke execute on function public.review_employee_document(uuid,text,text) from public; grant execute on function public.review_employee_document(uuid,text,text) to authenticated;
revoke execute on function public.save_asset_admin(uuid,text,text,text,text,text,text,text) from public; grant execute on function public.save_asset_admin(uuid,text,text,text,text,text,text,text) to authenticated;
revoke execute on function public.assign_asset_admin(uuid,uuid,text,text,text) from public; grant execute on function public.assign_asset_admin(uuid,uuid,text,text,text) to authenticated;
revoke execute on function public.return_asset_admin(uuid,text,text,text) from public; grant execute on function public.return_asset_admin(uuid,text,text,text) to authenticated;
revoke execute on function public.start_offboarding_case(uuid,text,text,date,date,uuid,jsonb) from public; grant execute on function public.start_offboarding_case(uuid,text,text,date,date,uuid,jsonb) to authenticated;
revoke execute on function public.transition_offboarding_clearance_item(uuid,text,text,text) from public; grant execute on function public.transition_offboarding_clearance_item(uuid,text,text,text) to authenticated;
revoke execute on function public.approve_offboarding_case(uuid,text,text) from public; grant execute on function public.approve_offboarding_case(uuid,text,text) to authenticated;
revoke execute on function public.get_documents_assets_offboarding_catalog(uuid) from public; grant execute on function public.get_documents_assets_offboarding_catalog(uuid) to authenticated;

commit;
