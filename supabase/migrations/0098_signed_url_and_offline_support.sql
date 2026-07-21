-- Migration 0098: Signed URL for report files + offline cache support

-- RPC: get_signed_url_for_path
-- Generates a short-lived signed URL for any storage path.
-- Used by the executive reports page to download report files.
-- Uses pg_net to call the Supabase Storage REST API (service role on server only).
create or replace function public.get_signed_url_for_path(
  p_bucket text,
  p_path text,
  p_ttl integer default 3600
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if not (public.current_is_full_access() or public.has_permission('reports.executive.read')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_bucket is null or p_path is null or length(trim(p_bucket)) = 0 or length(trim(p_path)) = 0 then
    raise exception 'INVALID_PATH';
  end if;

  -- storage.create_signed_url returns jsonb with 'signedUrl' key.
  select storage.create_signed_url(p_bucket, p_path, p_ttl) into v_result;

  if v_result is null then
    raise exception 'SIGN_FAILED';
  end if;

  return jsonb_build_object(
    'signedUrl', v_result ->> 'signedUrl',
    'expiresIn', p_ttl
  );
end;
$$;

revoke all on function public.get_signed_url_for_path(text, text, integer) from public;
grant execute on function public.get_signed_url_for_path(text, text, integer) to authenticated;

comment on function public.get_signed_url_for_path(text, text, integer) is
  'Generates a signed URL for accessing files in private storage buckets.';
