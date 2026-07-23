-- Unify web and Flutter employee photos on the public employee-avatars bucket.
-- Managers retain their existing rights; an authenticated user may manage only
-- objects under a folder named with their own auth.uid().

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'employee-avatars',
  'employee-avatars',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists employee_avatars_manage_write on storage.objects;
create policy employee_avatars_manage_write on storage.objects
  for insert to authenticated with check (
    bucket_id = 'employee-avatars'
    and (
      public.current_is_full_access()
      or public.has_permission('people.employee.create')
      or (storage.foldername(name))[1] = auth.uid()::text
    )
  );

drop policy if exists employee_avatars_manage_update on storage.objects;
create policy employee_avatars_manage_update on storage.objects
  for update to authenticated using (
    bucket_id = 'employee-avatars'
    and (
      public.current_is_full_access()
      or public.has_permission('people.employee.create')
      or (storage.foldername(name))[1] = auth.uid()::text
    )
  ) with check (
    bucket_id = 'employee-avatars'
    and (
      public.current_is_full_access()
      or public.has_permission('people.employee.create')
      or (storage.foldername(name))[1] = auth.uid()::text
    )
  );

drop policy if exists employee_avatars_manage_delete on storage.objects;
create policy employee_avatars_manage_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'employee-avatars'
    and (
      public.current_is_full_access()
      or public.has_permission('people.employee.create')
      or (storage.foldername(name))[1] = auth.uid()::text
    )
  );
