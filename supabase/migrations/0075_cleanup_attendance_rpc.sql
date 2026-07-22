-- Drop old signatures of record_attendance_event that used numeric for accuracy
-- This resolves the PGRST203 PostgREST ambiguity error when multiple functions exist.

drop function if exists public.record_attendance_event(uuid,text,double precision,double precision,numeric,text,text,uuid,boolean,boolean);
drop function if exists public.record_attendance_event(uuid,text,double precision,double precision,numeric,text,text,uuid,boolean);
