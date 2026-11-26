-- Migration 0739: Optimize RLS policies to evaluate auth.uid() once per statement (initPlan).
-- Wraps bare auth.uid() calls in (select auth.uid()) across 39 active policies without
-- altering any access predicate, role, command, or scope.

begin;

-- From 0038_release_access_privacy_integration_governance.sql: public.access_review_items :: access_review_items_read
drop policy if exists access_review_items_read on public.access_review_items;
create policy access_review_items_read on public.access_review_items for select to authenticated
using (reviewer_user_id = (select auth.uid()) or public.current_is_full_access() or public.has_any_permission(array['access.review.read','access.review.manage']));

-- From 0009_documents_tasks_policies.sql: public.attachments :: attachments_delete
drop policy if exists attachments_delete on public.attachments;
create policy attachments_delete on public.attachments
  for delete to authenticated
  using (public.has_permission('attachments.write') or created_by = (select auth.uid()) or public.current_is_full_access());

-- From 0009_documents_tasks_policies.sql: public.attachments :: attachments_insert
drop policy if exists attachments_insert on public.attachments;
create policy attachments_insert on public.attachments
  for insert to authenticated
  with check (public.has_permission('attachments.write') or created_by = (select auth.uid()));

-- From 0113_v10_request_attachment_catalog_access.sql: public.attachments :: attachments_select
drop policy if exists attachments_select on public.attachments;
create policy attachments_select on public.attachments
for select to authenticated using(
  created_by=(select auth.uid())
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

-- From 0009_documents_tasks_policies.sql: public.attachments :: attachments_update
drop policy if exists attachments_update on public.attachments;
create policy attachments_update on public.attachments
  for update to authenticated
  using (public.has_permission('attachments.write') or created_by = (select auth.uid()))
  with check (public.has_permission('attachments.write') or created_by = (select auth.uid()));

-- From 0038_release_access_privacy_integration_governance.sql: public.break_glass_requests :: break_glass_read
drop policy if exists break_glass_read on public.break_glass_requests;
create policy break_glass_read on public.break_glass_requests for select to authenticated
using (
  target_user_id = (select auth.uid()) or requested_by = (select auth.uid()) or approved_by = (select auth.uid())
  or public.current_is_full_access()
  or public.has_any_permission(array['access.break_glass.request','access.break_glass.approve'])
);

-- From 0033_talent_learning_documents_reports_notifications.sql: public.document_signature_requests :: signature_requests_read
drop policy if exists signature_requests_read on public.document_signature_requests;
create policy signature_requests_read on public.document_signature_requests for select to authenticated using (signer_user_id = (select auth.uid()) or public.current_is_full_access() or public.has_permission('documents.signature.manage'));

-- From 0073_location_security_hardening.sql: public.employee_devices :: emp_devices_select
drop policy if exists emp_devices_select on public.employee_devices;
create policy emp_devices_select on public.employee_devices
for select to authenticated using (
  user_id = (select auth.uid())
  or public.current_is_full_access()
  or public.has_permission('access.account.manage_devices')
);

-- From 0058_official_kpi_governance.sql: public.kpi_notification_receipts :: kpi_notification_receipts_read
drop policy if exists kpi_notification_receipts_read on public.kpi_notification_receipts;
create policy kpi_notification_receipts_read on public.kpi_notification_receipts for select to authenticated using(public.current_is_full_access() or recipient_user_id=(select auth.uid()));

-- From 0349_complete_rls_all_tables.sql: public.learning_enrollments :: learning_enrollments_read
drop policy if exists learning_enrollments_read on public.learning_enrollments;
CREATE POLICY learning_enrollments_read ON public.learning_enrollments
          FOR ALL TO authenticated USING (
            employee_id IN (SELECT employee_id FROM public.profiles WHERE id = (select auth.uid()))
            OR public.current_is_full_access()
            OR public.current_has_active_role(array['hr-manager', 'hr-specialist'])
          ) WITH CHECK (
            employee_id IN (SELECT employee_id FROM public.profiles WHERE id = (select auth.uid()))
            OR public.current_is_full_access()
            OR public.current_has_active_role(array['hr-manager', 'hr-specialist'])
          );

-- From 0038_release_access_privacy_integration_governance.sql: public.managed_devices :: managed_devices_read
drop policy if exists managed_devices_read on public.managed_devices;
create policy managed_devices_read on public.managed_devices for select to authenticated
using (user_id = (select auth.uid()) or public.current_is_full_access() or public.has_any_permission(array['system.release.read','system.release.manage','access.account.manage_devices']));

-- From 0008_communications_disputes.sql: public.notification_delivery_log :: notif_delivery_select
drop policy if exists notif_delivery_select on public.notification_delivery_log;
create policy notif_delivery_select on public.notification_delivery_log
  for select to authenticated
  using (recipient_user_id = (select auth.uid()) or public.current_is_full_access() or public.has_permission('comms.notification.admin'));

-- From 0008_communications_disputes.sql: public.notifications :: notifications_delete
drop policy if exists notifications_delete on public.notifications;
create policy notifications_delete on public.notifications
  for delete to authenticated
  using (recipient_user_id = (select auth.uid()));

-- From 0008_communications_disputes.sql: public.notifications :: notifications_select
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications
  for select to authenticated
  using (recipient_user_id = (select auth.uid()) or public.current_is_full_access());

-- From 0008_communications_disputes.sql: public.notifications :: notifications_update
drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications
  for update to authenticated
  using (recipient_user_id = (select auth.uid()))
  with check (recipient_user_id = (select auth.uid()));

-- From 0038_release_access_privacy_integration_governance.sql: public.privacy_requests :: privacy_requests_read
drop policy if exists privacy_requests_read on public.privacy_requests;
create policy privacy_requests_read on public.privacy_requests for select to authenticated
using (requester_user_id = (select auth.uid()) or assigned_to = (select auth.uid()) or public.current_is_full_access() or public.has_permission('privacy.request.manage'));

-- From 0004_employees.sql: public.profiles :: profiles_delete
drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles
  for delete to authenticated
  using (
    (public.current_is_full_access() or public.has_permission('profiles.manage'))
    and id is distinct from (select auth.uid())
  );

-- From 0004_employees.sql: public.profiles :: profiles_select
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or public.current_is_full_access()
    or public.has_permission('profiles.read')
  );

-- From 0004_employees.sql: public.profiles :: profiles_update
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (
    id = (select auth.uid())
    or public.current_is_full_access()
    or public.has_permission('profiles.manage')
  )
  with check (
    id = (select auth.uid())
    or public.current_is_full_access()
    or public.has_permission('profiles.manage')
  );

-- From 0008_communications_disputes.sql: public.push_subscriptions :: push_subs_delete
drop policy if exists push_subs_delete on public.push_subscriptions;
create policy push_subs_delete on public.push_subscriptions
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- From 0008_communications_disputes.sql: public.push_subscriptions :: push_subs_insert
drop policy if exists push_subs_insert on public.push_subscriptions;
create policy push_subs_insert on public.push_subscriptions
  for insert to authenticated
  with check (user_id = (select auth.uid()));

-- From 0008_communications_disputes.sql: public.push_subscriptions :: push_subs_select
drop policy if exists push_subs_select on public.push_subscriptions;
create policy push_subs_select on public.push_subscriptions
  for select to authenticated
  using (user_id = (select auth.uid()) or public.current_is_full_access());

-- From 0008_communications_disputes.sql: public.push_subscriptions :: push_subs_update
drop policy if exists push_subs_update on public.push_subscriptions;
create policy push_subs_update on public.push_subscriptions
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- From 0035_enterprise_strategy_projects_service_governance.sql: public.service_request_messages :: service_messages_create
drop policy if exists service_messages_create on public.service_request_messages;
create policy service_messages_create on public.service_request_messages for insert to authenticated with check(author_user_id=(select auth.uid()) and exists(select 1 from public.service_requests r where r.id=request_id and (r.requester_employee_id=public.current_employee_id() or r.assigned_to_employee_id=public.current_employee_id() or public.current_is_full_access() or public.has_permission('service.request.manage'))));

-- From 0011_audit_security_system.sql: public.settings :: settings_select
drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings
  for select to authenticated
  using (
    is_public
    or public.current_is_full_access()
    or public.has_any_permission(array['settings.read','settings.manage'])
    or (scope = 'user' and scope_id = (select auth.uid()))
  );

-- From 0011_audit_security_system.sql: public.settings :: settings_write_own
drop policy if exists settings_write_own on public.settings;
create policy settings_write_own on public.settings
  for all to authenticated
  using (scope = 'user' and scope_id = (select auth.uid()))
  with check (scope = 'user' and scope_id = (select auth.uid()));

-- From 0227_critical_rpc_authz_hardening.sql: public.survey_responses :: survey_responses_insert
drop policy if exists survey_responses_insert on public.survey_responses;
CREATE POLICY survey_responses_insert ON public.survey_responses
  FOR INSERT TO authenticated
  WITH CHECK (
    
    EXISTS (
      SELECT 1 FROM public.surveys s
      WHERE s.id = survey_id AND s.status = 'open'
    )
    
    AND created_by = (select auth.uid())
  );

-- From 0009_documents_tasks_policies.sql: public.ticket_messages :: ticket_messages_delete
drop policy if exists ticket_messages_delete on public.ticket_messages;
create policy ticket_messages_delete on public.ticket_messages
  for delete to authenticated
  using (author_id = (select auth.uid()) or public.has_permission('tickets.write') or public.current_is_full_access());

-- From 0009_documents_tasks_policies.sql: public.ticket_messages :: ticket_messages_update
drop policy if exists ticket_messages_update on public.ticket_messages;
create policy ticket_messages_update on public.ticket_messages
  for update to authenticated
  using (author_id = (select auth.uid()) or public.has_permission('tickets.write'))
  with check (author_id = (select auth.uid()) or public.has_permission('tickets.write'));

-- From 0002_permissions_roles_functions.sql: public.user_roles :: user_roles_read
drop policy if exists user_roles_read on public.user_roles;
create policy user_roles_read on public.user_roles for select to authenticated
  using (user_id = (select auth.uid()) or public.has_permission('access.role.assign'));

-- From 0036_workforce_compensation_payroll_engagement.sql: public.wellbeing_requests :: wellbeing_requests_manage
drop policy if exists wellbeing_requests_manage on public.wellbeing_requests;
create policy wellbeing_requests_manage on public.wellbeing_requests for update to authenticated using(assigned_specialist_user_id=(select auth.uid()) or public.current_is_full_access() or public.has_permission('wellbeing.request.manage')) with check(assigned_specialist_user_id=(select auth.uid()) or public.current_is_full_access() or public.has_permission('wellbeing.request.manage'));

-- From 0036_workforce_compensation_payroll_engagement.sql: public.wellbeing_requests :: wellbeing_requests_owner
drop policy if exists wellbeing_requests_owner on public.wellbeing_requests;
create policy wellbeing_requests_owner on public.wellbeing_requests for select to authenticated using(employee_id=public.current_employee_id() or assigned_specialist_user_id=(select auth.uid()) or public.current_is_full_access() or public.has_permission('wellbeing.request.manage'));

-- From 0114_unify_employee_avatar_storage.sql: storage.objects :: employee_avatars_manage_delete
drop policy if exists employee_avatars_manage_delete on storage.objects;
create policy employee_avatars_manage_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'employee-avatars'
    and (
      public.current_is_full_access()
      or public.has_permission('people.employee.create')
      or (storage.foldername(name))[1] = (select auth.uid())::text
    )
  );

-- From 0114_unify_employee_avatar_storage.sql: storage.objects :: employee_avatars_manage_update
drop policy if exists employee_avatars_manage_update on storage.objects;
create policy employee_avatars_manage_update on storage.objects
  for update to authenticated using (
    bucket_id = 'employee-avatars'
    and (
      public.current_is_full_access()
      or public.has_permission('people.employee.create')
      or (storage.foldername(name))[1] = (select auth.uid())::text
    )
  ) with check (
    bucket_id = 'employee-avatars'
    and (
      public.current_is_full_access()
      or public.has_permission('people.employee.create')
      or (storage.foldername(name))[1] = (select auth.uid())::text
    )
  );

-- From 0114_unify_employee_avatar_storage.sql: storage.objects :: employee_avatars_manage_write
drop policy if exists employee_avatars_manage_write on storage.objects;
create policy employee_avatars_manage_write on storage.objects
  for insert to authenticated with check (
    bucket_id = 'employee-avatars'
    and (
      public.current_is_full_access()
      or public.has_permission('people.employee.create')
      or (storage.foldername(name))[1] = (select auth.uid())::text
    )
  );

-- From 0177_v23_announcements_storage_notifications.sql: storage.objects :: owner_delete_announcements
drop policy if exists owner_delete_announcements on storage.objects;
create policy "owner_delete_announcements"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'announcements' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- From 0112_v10_request_acceptance_repairs.sql: storage.objects :: request_attachments_storage_delete
drop policy if exists request_attachments_storage_delete on storage.objects;
create policy request_attachments_storage_delete on storage.objects
for delete to authenticated using(
  bucket_id='request-attachments'
  and (storage.foldername(name))[1]=(select auth.uid())::text
);

-- From 0112_v10_request_acceptance_repairs.sql: storage.objects :: request_attachments_storage_insert
drop policy if exists request_attachments_storage_insert on storage.objects;
create policy request_attachments_storage_insert on storage.objects
for insert to authenticated with check(
  bucket_id='request-attachments'
  and (storage.foldername(name))[1]=(select auth.uid())::text
);

-- From 0112_v10_request_acceptance_repairs.sql: storage.objects :: request_attachments_storage_read
drop policy if exists request_attachments_storage_read on storage.objects;
create policy request_attachments_storage_read on storage.objects
for select to authenticated using(
  bucket_id='request-attachments' and (
    (storage.foldername(name))[1]=(select auth.uid())::text
    or exists(
      select 1
      from public.attachments a
      join public.requests r on r.id=a.entity_id
      where a.entity_type='request' and a.storage_path=name
        and (
          r.employee_id=public.current_employee_id()
          or r.manager_employee_id=public.current_employee_id()
          or public.current_is_full_access()
          or public.can_access_employee(r.employee_id,'requests.request.read')
          or public.can_access_employee(r.employee_id,'requests.request.approve')
        )
    )
  )
);

commit;
