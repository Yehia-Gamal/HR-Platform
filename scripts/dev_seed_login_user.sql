-- Dev-only: create a real login user for local Supabase so the mobile app can
-- sign in end-to-end. Idempotent. Credentials:
--   email:    demo@ahla.local
--   password: Passw0rd!123
--
-- Run with:
--   docker exec -i supabase_db_ahla-shabab-management-os-v8 \
--     psql -U postgres -d postgres < scripts/dev_seed_login_user.sql

begin;

do $$
declare
  v_email    text := 'demo@ahla.local';
  v_password text := 'Passw0rd!123';
  v_user_id  uuid;
  v_role_slug text := 'admin';
begin
  -- Reuse existing auth user if present, else create one with a bcrypt password.
  select id into v_user_id from auth.users where email = v_email;

  if v_user_id is null then
    v_user_id := gen_random_uuid();
    -- NOTE: GoTrue (Postgres 15/17, GoTrue v2.19x) scans the string token
    -- columns as NOT-NULL Go strings on sign-in. A manual INSERT that leaves
    -- them NULL makes password sign-in fail with a 500
    -- "Database error querying schema" (GoTrue cannot scan NULL into string).
    -- The managed admin.createUser() API sets these to '' automatically; when
    -- inserting directly we must set them to '' ourselves.
    insert into auth.users (
      id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change,
      email_change_token_new, email_change_token_current,
      phone_change, phone_change_token, reauthentication_token,
      created_at, updated_at
    ) values (
      v_user_id,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      v_email,
      crypt(v_password, gen_salt('bf')),
      now(),
      jsonb_build_object('provider', 'email', 'providers', array['email']),
      jsonb_build_object('full_name_ar', 'مستخدم تجريبي', 'employee_code', 'DEMO001'),
      '', '', '',
      '', '',
      '', '', '',
      now(),
      now()
    );

    -- GoTrue expects an identities row for email logins.
    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(),
      v_user_id,
      v_user_id::text,
      jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true),
      'email',
      now(), now(), now()
    );
  else
    -- Refresh the password so it always matches the documented credentials, and
    -- backfill any NULL token columns to '' (rows created by an older version of
    -- this script would otherwise still fail sign-in with a 500 on PG15/17).
    update auth.users
       set encrypted_password         = crypt(v_password, gen_salt('bf')),
           email_confirmed_at         = coalesce(email_confirmed_at, now()),
           confirmation_token         = coalesce(confirmation_token, ''),
           recovery_token             = coalesce(recovery_token, ''),
           email_change               = coalesce(email_change, ''),
           email_change_token_new     = coalesce(email_change_token_new, ''),
           email_change_token_current = coalesce(email_change_token_current, ''),
           phone_change               = coalesce(phone_change, ''),
           phone_change_token         = coalesce(phone_change_token, ''),
           reauthentication_token     = coalesce(reauthentication_token, ''),
           updated_at                 = now()
     where id = v_user_id;
  end if;

  -- Provision the employee/profile/role chain only if not already present.
  if not exists (select 1 from public.profiles where id = v_user_id) then
    perform public.provision_employee_record(
      p_actor_user_id     => v_user_id,
      p_user_id           => v_user_id,
      p_full_name_ar      => 'مستخدم تجريبي',
      p_full_name_en      => 'Demo User',
      p_employee_code     => 'DEMO001',
      p_phone_e164        => '+201000000001',
      p_role_slug         => v_role_slug,
      p_invitation_pending => false
    );
  end if;

  raise notice 'Demo user ready: % (%).', v_email, v_user_id;
end $$;

commit;

-- Verification output.
select u.email, p.status as profile_status, e.employee_code, e.full_name_ar, r.slug as role
from auth.users u
join public.profiles p on p.id = u.id
join public.employees e on e.id = p.employee_id
join public.roles r on r.id = p.primary_role_id
where u.email = 'demo@ahla.local';
