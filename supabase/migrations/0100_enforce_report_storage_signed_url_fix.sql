-- Migration 0100: forward-only production repair for the report Storage
-- signed-URL flow. Migration 0099 was already recorded remotely before its
-- local correction, so this migration applies the repair to existing stacks.

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
