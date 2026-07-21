-- Migration 0099: replace the invalid SQL Storage signer with RLS-backed
-- signed URLs created through the supported Storage API.

-- Supabase Storage does not expose storage.create_signed_url(...) as a SQL
-- function. Migration 0098 could therefore be installed, but every call to
-- get_signed_url_for_path failed at runtime. Remove that unsafe generic RPC;
-- the authenticated client signs only objects it can SELECT through RLS.
drop function if exists public.get_signed_url_for_path(text, text, integer);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'report-files',
  'report-files',
  false,
  52428800,
  array[
    'application/pdf',
    'text/csv',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists report_files_authorized_read on storage.objects;
create policy report_files_authorized_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'report-files'
  and (
    public.current_is_full_access()
    or public.has_permission('reports.executive.read')
    or public.has_permission('reports.schedule.manage')
  )
);
