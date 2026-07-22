-- Migration 0034: private storage buckets and access policies.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values
 ('employee-documents','employee-documents',false,10485760,array['application/pdf','image/jpeg','image/png','application/vnd.openxmlformats-officedocument.wordprocessingml.document']),
 ('candidate-documents','candidate-documents',false,10485760,array['application/pdf','image/jpeg','image/png','application/vnd.openxmlformats-officedocument.wordprocessingml.document']),
 ('generated-documents','generated-documents',false,15728640,array['application/pdf']),
 ('course-materials','course-materials',false,52428800,array['application/pdf','video/mp4','image/jpeg','image/png']),
 ('live-location-videos','live-location-videos',false,15728640,array['video/mp4','video/quicktime'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- Employee documents: employee own prefix or authorized document manager.
drop policy if exists employee_documents_storage_read on storage.objects;
create policy employee_documents_storage_read on storage.objects for select to authenticated using (
 bucket_id='employee-documents' and (public.current_is_full_access() or public.has_permission('documents.employee.read') or (storage.foldername(name))[1]=coalesce(public.current_employee_id()::text,''))
);
drop policy if exists employee_documents_storage_write on storage.objects;
create policy employee_documents_storage_write on storage.objects for insert to authenticated with check (
 bucket_id='employee-documents' and (public.current_is_full_access() or public.has_permission('documents.employee.manage') or (storage.foldername(name))[1]=coalesce(public.current_employee_id()::text,''))
);

-- Recruitment files are private to recruitment staff.
drop policy if exists candidate_documents_storage_read on storage.objects;
create policy candidate_documents_storage_read on storage.objects for select to authenticated using (bucket_id='candidate-documents' and (public.current_is_full_access() or public.has_any_permission(array['recruitment.candidate.read','recruitment.candidate.manage'])));
drop policy if exists candidate_documents_storage_write on storage.objects;
create policy candidate_documents_storage_write on storage.objects for insert to authenticated with check (bucket_id='candidate-documents' and (public.current_is_full_access() or public.has_permission('recruitment.candidate.manage')));

-- Generated documents and learning materials.
drop policy if exists generated_documents_storage_read on storage.objects;
create policy generated_documents_storage_read on storage.objects for select to authenticated using (bucket_id='generated-documents' and (public.current_is_full_access() or public.has_any_permission(array['documents.generated.manage','documents.signature.manage'])));
drop policy if exists generated_documents_storage_write on storage.objects;
create policy generated_documents_storage_write on storage.objects for insert to authenticated with check (bucket_id='generated-documents' and (public.current_is_full_access() or public.has_permission('documents.generated.manage')));

drop policy if exists course_materials_storage_read on storage.objects;
create policy course_materials_storage_read on storage.objects for select to authenticated using (bucket_id='course-materials');
drop policy if exists course_materials_storage_write on storage.objects;
create policy course_materials_storage_write on storage.objects for insert to authenticated with check (bucket_id='course-materials' and (public.current_is_full_access() or public.has_permission('learning.course.manage')));

-- Live verification video is never generally readable; access is through short signed URLs created by trusted server code.
drop policy if exists live_location_videos_owner_write on storage.objects;
create policy live_location_videos_owner_write on storage.objects for insert to authenticated with check (bucket_id='live-location-videos' and (storage.foldername(name))[1]=coalesce(public.current_employee_id()::text,''));
