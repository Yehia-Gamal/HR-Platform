-- 0250: Keep KPI external-link validation aligned with the hardened URL/path
-- validators.  0243 normalized only selected checks, which left a leading
-- whitespace scheme and mixed slash/backslash traversal able to bypass the
-- generic-scheme and traversal guards.

begin;

create or replace function public.is_safe_external_link(p_value text)
returns boolean
language sql
immutable
parallel safe
as $$
  with normalized as (select ltrim($1) as value)
  select case
    when $1 is null or length(trim($1)) = 0 then true
    when $1 ~ '[[:cntrl:]]' then false
    when lower((select value from normalized)) ~
         '^(data|file|javascript|blob|vbscript|about|filesystem):' then false
    when (select value from normalized) ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:'
         and lower((select value from normalized)) !~ '^https?://' then false
    when (select value from normalized) ~ '^[/\\]{2}' then false
    when (select value from normalized) ~ '(^|[/\\])\.\.([/\\]|$)' then false
    else true
  end;
$$;

revoke all on function public.is_safe_external_link(text) from public;
grant execute on function public.is_safe_external_link(text) to authenticated, service_role;

commit;
