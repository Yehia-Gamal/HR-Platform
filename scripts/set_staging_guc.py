#!/usr/bin/env python3
"""Set GUC settings and verify push pipeline on Supabase staging."""
import json
import secrets
import sys

import os

try:
    import psycopg2
except ImportError:
    print("Installing psycopg2...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"])
    import psycopg2

DB_URL = os.environ.get("SUPABASE_DB_URL", "postgresql://postgres:YOUR_PASSWORD@db.ujzzvqsodyhnnnpkoaml.supabase.co:5432/postgres")
FUNCTIONS_BASE_URL = "https://ujzzvqsodyhnnnpkoaml.supabase.co/functions/v1"

def main():
    cron_secret = secrets.token_urlsafe(32)

    print("Connecting to staging database...")
    conn = psycopg2.connect(DB_URL, connect_timeout=15)
    conn.autocommit = True
    cur = conn.cursor()

    # Set GUC settings
    print("[1] Setting app.settings.functions_base_url...")
    cur.execute(f"ALTER DATABASE postgres SET app.settings.functions_base_url = %s;", (FUNCTIONS_BASE_URL,))
    print(f"    OK: {FUNCTIONS_BASE_URL}")

    print("[2] Setting app.settings.cron_secret...")
    cur.execute(f"ALTER DATABASE postgres SET app.settings.cron_secret = %s;", (cron_secret,))
    print(f"    OK: [{len(cron_secret)} chars]")

    # Verify
    print("[3] Verifying (pg_db_role_setting)...")
    cur.execute("""
        SELECT setconfig FROM pg_db_role_setting
        WHERE setdatabase = (SELECT oid FROM pg_database WHERE datname = 'postgres')
        AND setrole = 0;
    """)
    row = cur.fetchone()
    if row and row[0]:
        for c in row[0]:
            if 'functions_base_url' in c:
                print(f"    OK: {c}")
            elif 'cron_secret' in c:
                print(f"    OK: app.settings.cron_secret = [SET]")

    # Check push_subscriptions for any active FCM tokens
    print("[4] Checking push_subscriptions for active FCM tokens...")
    cur.execute("SELECT count(*) FROM push_subscriptions WHERE fcm_token IS NOT NULL AND is_active;")
    count = cur.fetchone()[0]
    print(f"    Active FCM subscriptions: {count}")

    # Check notification_jobs status
    print("[5] Checking notification_jobs queue...")
    cur.execute("""
        SELECT status, count(*) FROM notification_jobs
        GROUP BY status ORDER BY count(*) DESC;
    """)
    for row in cur.fetchall():
        print(f"    {row[0]}: {row[1]}")

    # Check if FCM_SERVICE_ACCOUNT_JSON exists as edge secret
    print("[6] Checking FCM_SERVICE_ACCOUNT_JSON...")
    # We can't read edge secrets from DB, but we can check if notification-dispatcher
    # would work by looking at delivery logs
    cur.execute("""
        SELECT status, count(*), max(created_at) as latest
        FROM notification_delivery_log
        WHERE channel = 'push'
        GROUP BY status;
    """)
    rows = cur.fetchall()
    if rows:
        for row in rows:
            print(f"    Push delivery {row[0]}: {row[1]} (latest: {row[2]})")
    else:
        print("    No push delivery logs yet")

    # Write the cron_secret to a temp file for the supabase CLI to use
    secret_file = "scripts/.cron_secret_staging.tmp"
    with open(secret_file, "w") as f:
        f.write(cron_secret)
    print(f"\n[!] CRON_SECRET saved to {secret_file}")
    print(f"    Run: npx supabase secrets set CRON_SECRET=$(cat {secret_file}) --project-ref ujzzvqsodyhnnnpkoaml")

    cur.close()
    conn.close()

    print("\n" + "=" * 50)
    print("DONE. GUC settings applied to staging.")
    print("=" * 50)

if __name__ == "__main__":
    main()
