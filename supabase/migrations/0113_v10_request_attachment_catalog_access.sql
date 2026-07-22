-- Allow request reviewers to resolve attachment catalog rows used by the
-- private Storage read policy. Other attachment entity types retain their
-- existing permission boundary.
begin;

drop policy if exists attachments_select on public.attachments;
create policy attachments_select on public.attachments
for select to authenticated using(
  created_by=auth.uid()
  or public.current_is_full_access()
  or (
    entity_type='request'
    and exists(
      select 1 from public.requests r
      where r.id=attachments.entity_id and (
        r.employee_id=public.current_employee_id()
        or r.manager_employee_id=public.current_employee_id()
        or public.can_access_employee(r.employee_id,'requests.request.read')
        or public.can_access_employee(r.employee_id,'requests.request.approve')
      )
    )
  )
  or (
    entity_type<>'request'
    and public.has_any_permission(array['attachments.read','documents.read'])
  )
);

commit;
