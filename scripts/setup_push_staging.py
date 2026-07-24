#!/usr/bin/env python3
"""Set push pipeline config on Supabase staging - uses psycopg2 for DB, prints CLI commands for secrets."""
import json, secrets, sys, os
try:
    import psycopg2
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"])
    import psycopg2

DB = os.environ.get("SUPABASE_DB_URL", "postgresql://postgres:YOUR_PASSWORD@db.ujzzvqsodyhnnnpkoaml.supabase.co:5432/postgres")
BASE = "https://ujzzvqsodyhnnnpkoaml.supabase.co/functions/v1"

conn = psycopg2.connect(DB, connect_timeout=15)
conn.autocommit = True
cur = conn.cursor()

cs = secrets.token_urlsafe(32)

print("[1] Trying ALTER ROLE postgres SET (instead of ALTER DATABASE)...")
try:
    cur.execute("ALTER ROLE postgres SET app.settings.functions_base_url = %s;", (BASE,))
    print("    OK: functions_base_url set")
except Exception as e:
    print(f"    FAIL: {e}")

try:
    cur.execute("ALTER ROLE postgres SET app.settings.cron_secret = %s;", (cs,))
    print(f"    OK: cron_secret set [{len(cs)} chars]")
except Exception as e:
    print(f"    FAIL: {e}")

print("\n[2] Verifying role settings...")
cur.execute("SELECT rolconfig FROM pg_roles WHERE rolname = 'postgres';")
row = cur.fetchone()
if row and row[0]:
    for c in row[0]:
        if 'functions_base_url' in c:
            print(f"    OK: {c}")
        elif 'cron_secret' in c:
            print(f"    OK: cron_secret = [SET]")
else:
    print("    No role config found")

print("\n[3] Checking pg_cron jobs...")
try:
    cur.execute("SELECT jobname, schedule, command FROM cron.job WHERE jobname LIKE 'hr_%' ORDER BY jobname;")
    for row in cur.fetchall():
        cmd_preview = row[2][:80] + "..." if len(row[2]) > 80 else row[2]
        print(f"    {row[0]}: {row[1]} -> {cmd_preview}")
except Exception as e:
    print(f"    pg_cron not available or no jobs: {e}")

print("\n[4] Checking push_subscriptions...")
cur.execute("SELECT count(*) as total, count(fcm_token) as with_fcm, count(*) FILTER (WHERE is_active AND fcm_token IS NOT NULL) as active_fcm FROM push_subscriptions;")
row = cur.fetchone()
print(f"    Total: {row[0]}, With FCM token: {row[1]}, Active FCM: {row[2]}")

print("\n[5] Checking notification_jobs queue...")
cur.execute("SELECT status, count(*) FROM notification_jobs GROUP BY status ORDER BY count(*) DESC LIMIT 5;")
for row in cur.fetchall():
    print(f"    {row[0]}: {row[1]}")

print("\n[6] Checking notification_delivery_log...")
cur.execute("SELECT status, count(*), max(created_at)::text FROM notification_delivery_log WHERE channel='push' GROUP BY status;")
rows = cur.fetchall()
if rows:
    for row in rows:
        print(f"    {row[0]}: {row[1]} (latest: {row[2]})")
else:
    print("    No push delivery logs yet")

# Save cron secret
with open("scripts/.cron_secret.tmp", "w") as f:
    f.write(cs)

print(f"\n[NEXT] Sync CRON_SECRET to Edge Function secret:")
print(f"  export SUPABASE_ACCESS_TOKEN=$SUPABASE_ACCESS_TOKEN")
print(f"  npx supabase secrets set CRON_SECRET={cs} --project-ref ujzzvqsodyhnnnpkoaml")

cur.close()
conn.close()
print("\nDone.")
