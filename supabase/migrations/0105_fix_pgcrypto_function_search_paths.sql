-- 0105: pgcrypto is installed in the extensions schema. Keep SECURITY DEFINER
-- search paths explicit while making digest() available to device functions.

alter function public.register_my_device(
  text,text,text,text,text,text,integer,text,boolean,boolean,jsonb
) set search_path = public, extensions, pg_temp;

alter function public.get_my_attendance_state()
  set search_path = public, extensions, pg_temp;

alter function public.punch_attendance_local_biometric_v1(
  uuid,text,text,double precision,double precision,double precision,boolean
) set search_path = public, extensions, pg_temp;

alter function public.finalize_verified_attendance(
  uuid,uuid,uuid,uuid,uuid,uuid,text,double precision,double precision,
  double precision,bigint,text,boolean
) set search_path = public, extensions, pg_temp;

notify pgrst, 'reload schema';
