-- 0249: Normalize leading whitespace and reject mixed slash/backslash escapes.

begin;

create or replace function public.is_safe_url_or_path(p_value text)
returns boolean
language sql
immutable
parallel safe
as $$
  with normalized as (select ltrim($1) as value)
  select case
    when $1 is null or length(trim($1)) = 0 then true
    when $1 ~ '[[:cntrl:]]' then false
    when lower((select value from normalized)) ~ '^(data|file|javascript|blob|vbscript|about|filesystem):' then false
    when (select value from normalized) ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:'
         and lower((select value from normalized)) !~ '^https://' then false
    when (select value from normalized) ~ '^[/\\]{2}' then false
    when (select value from normalized) ~ '(^|[/\\])\.\.([/\\]|$)' then false
    else true
  end;
$$;

create or replace function public.is_safe_storage_path(p_value text)
returns boolean
language sql
immutable
parallel safe
as $$
  with normalized as (select ltrim($1) as value)
  select case
    when $1 is null or length(trim($1)) = 0 then true
    when $1 ~ '[[:cntrl:]]' then false
    when (select value from normalized) ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:' then false
    when (select value from normalized) ~ '^[/\\]' then false
    when (select value from normalized) ~ '(^|[/\\])\.\.([/\\]|$)' then false
    else true
  end;
$$;

revoke all on function public.is_safe_url_or_path(text) from public;
revoke all on function public.is_safe_storage_path(text) from public;
grant execute on function public.is_safe_url_or_path(text) to authenticated, service_role;
grant execute on function public.is_safe_storage_path(text) to authenticated, service_role;

commit;
