-- 0400: drop the legacy 4-arg submit_my_request overload
--
-- Migration 0379 added submit_my_request(text,text,text,jsonb,uuid) with
-- DEFAULT '{}' on p_payload and DEFAULT null on p_idempotency_key. Because the
-- old 4-arg overload submit_my_request(text,text,text,jsonb) still exists, a
-- call with 4 args matches BOTH candidates and Postgres raises
--   function public.submit_my_request(text, text, text, jsonb) is not unique
-- This breaks every existing caller (tests 0032/0039/0045/0056/0098/0108/
-- 0110/0111/0116, old web/mobile clients via PostgREST, ...).
--
-- The 5-arg overload is a strict superset of the 4-arg one (same params, same
-- defaults, plus optional p_idempotency_key). Keeping only it resolves the
-- ambiguity with zero behavior change for existing callers.

begin;

drop function if exists public.submit_my_request(text, text, text, jsonb);

commit;
