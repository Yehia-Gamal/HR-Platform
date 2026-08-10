-- Delete admin@ahla.local: reassign all FK references to يحيى, then drop user
DO $$
DECLARE
  r RECORD;
  v_old uuid := '4d67a42c-cc41-4f5f-82f0-bffea79356f2';
  v_new uuid := '6f347a78-bb30-4ae5-8b07-2ecfc623f960';
BEGIN
  -- Delete user-ownership rows (personal data, not audit trail)
  DELETE FROM push_subscriptions WHERE user_id = v_old;
  DELETE FROM password_reset_requests WHERE user_id = v_old;
  DELETE FROM passkey_credentials WHERE user_id = v_old;
  DELETE FROM ticket_messages WHERE author_id = v_old;
  DELETE FROM break_glass_requests WHERE target_user_id = v_old;

  -- Reassign all remaining FK columns to يحيى
  FOR r IN
    SELECT
      conrelid::regclass::text AS tbl,
      (SELECT a.attname FROM pg_attribute a
       WHERE a.attrelid = conrelid AND a.attnum = conkey[1]) AS col
    FROM pg_constraint
    WHERE contype = 'f'
      AND confrelid = 'auth.users'::regclass
      AND connamespace = 'public'::regnamespace
  LOOP
    BEGIN
      EXECUTE format('UPDATE %s SET %I = $1 WHERE %I = $2', r.tbl, r.col, r.col)
        USING v_new, v_old;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skip %.%: %', r.tbl, r.col, SQLERRM;
    END;
  END LOOP;

  -- Delete any remaining auth-internal references (sessions, identities, etc.)
  DELETE FROM auth.sessions WHERE user_id = v_old;
  DELETE FROM auth.identities WHERE user_id = v_old;
  DELETE FROM auth.mfa_factors WHERE user_id = v_old;
  DELETE FROM auth.oauth_authorizations WHERE user_id = v_old;
  DELETE FROM auth.oauth_consents WHERE user_id = v_old;
  DELETE FROM auth.one_time_tokens WHERE user_id = v_old;
  DELETE FROM auth.webauthn_challenges WHERE user_id = v_old;
  DELETE FROM auth.webauthn_credentials WHERE user_id = v_old;

  -- Finally, delete the auth user
  DELETE FROM auth.users WHERE id = v_old;
END $$;
