#!/usr/bin/env python3
"""Set push pipeline config on Supabase staging via direct DB + CLI."""
import json, secrets, subprocess, os, sys

try:
    import psycopg2
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"])
    import psycopg2

DB = os.environ.get("SUPABASE_DB_URL", "postgresql://postgres:YOUR_PASSWORD@db.ujzzvqsodyhnnnpkoaml.supabase.co:5432/postgres")
REF = "ujzzvqsodyhnnnpkoaml"
FURL = "https://ujzzvqsodyhnnnpkoaml.supabase.co/functions/v1"

conn = psycopg2.connect(DB, connect_timeout=15)
conn.autocommit = True
cur = conn.cursor()

print("[1] Checking pg_cron + pg_net status...")
cur.execute("SELECT extname FROM pg_extension WHERE extname IN ('pg_cron','pg_net') ORDER BY 1;")
for r in cur.fetchall():
    print(f"    extension: {r[0]}")

print("[2] Checking existing cron jobs...")
try:
    cur.execute("SELECT jobid, jobname, schedule FROM cron.job ORDER BY jobname;")
    for r in cur.fetchall():
        print(f"    job {r[0]}: {r[1]} ({r[2]})")
except Exception as e:
    print(f"    {e}")

print("[3] Checking notification_jobs queue...")
cur.execute("SELECT status, count(*) FROM notification_jobs GROUP BY status;")
for r in cur.fetchall():
    print(f"    {r[0]}: {r[1]}")

print("[4] Checking push_subscriptions...")
cur.execute("SELECT count(*) FROM push_subscriptions WHERE is_active AND fcm_token IS NOT NULL;")
print(f"    Active FCM tokens: {cur.fetchone()[0]}")
cur.execute("SELECT count(*) FROM push_subscriptions WHERE is_active;")
print(f"    Total active subs: {cur.fetchone()[0]}")

print("[5] Checking notification_delivery_log...")
cur.execute("SELECT status, count(*) FROM notification_delivery_log GROUP BY status;")
rows = cur.fetchall()
if rows:
    for r in rows:
        print(f"    {r[0]}: {r[1]}")
else:
    print("    (empty)")

print("[6] Trying ALTER ROLE for GUC settings...")
try:
    cur.execute(f"ALTER ROLE postgres SET app.settings.functions_base_url = '{FURL}';")
    print(f"    functions_base_url: OK")
except Exception as e:
    print(f"    functions_base_url FAILED: {e}")
    conn.rollback() if not conn.autocommit else None

cs = secrets.token_urlsafe(32)
try:
    cur.execute(f"ALTER ROLE postgres SET app.settings.cron_secret = %s;", (cs,))
    print(f"    cron_secret: OK [{len(cs)} chars]")
    with open("scripts/.cron_secret.tmp", "w") as f:
        f.write(cs)
except Exception as e:
    print(f"    cron_secret FAILED: {e}")

print("[7] Checking latest notifications for live_location_request...")
cur.execute("""
    SELECT id, title, priority, (metadata->>'fullScreen')::text as fs,
           (metadata->>'deepLink')::text as dl, created_at
    FROM notifications
    WHERE entity_type = 'live_location_request'
    ORDER BY created_at DESC LIMIT 3;
""")
for r in cur.fetchall():
    print(f"    {r[5]}: {r[1]} | priority={r[2]} fullScreen={r[3]}")

cur.close()
conn.close()
print("\nDone.")
