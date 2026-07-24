#!/usr/bin/env python3
"""Check and fix push pipeline on Supabase staging."""
import json, secrets, sys, os

try:
    import psycopg2
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"])
    import psycopg2

DB = os.environ.get("SUPABASE_DB_URL", "postgresql://postgres:YOUR_PASSWORD@db.ujzzvqsodyhnnnpkoaml.supabase.co:5432/postgres")
PROJ = "ujzzvqsodyhnnnpkoaml"
BASE = f"https://{PROJ}.supabase.co/functions/v1"

conn = psycopg2.connect(DB, connect_timeout=15)
conn.autocommit = True
cur = conn.cursor()

def q(sql):
    cur.execute(sql)
    try: return cur.fetchall()
    except: return []

print("=== 1. Check pg_cron jobs ===")
try:
    rows = q("SELECT jobname, schedule, command FROM cron.job WHERE jobname LIKE 'hr_%';")
    for r in rows:
        print(f"  {r[0]}: {r[1]}")
        if 'notification' in r[0]:
            print(f"    cmd: {r[2][:120]}...")
    if not rows:
        print("  NO cron jobs found!")
except Exception as e:
    print(f"  pg_cron not available: {e}")

print("\n=== 2. Check notification_jobs queue ===")
rows = q("SELECT status, count(*) FROM notification_jobs GROUP BY status;")
for r in rows: print(f"  {r[0]}: {r[1]}")
if not rows: print("  Empty queue")

print("\n=== 3. Check push_subscriptions ===")
rows = q("SELECT count(*), count(fcm_token) FILTER (WHERE fcm_token IS NOT NULL AND is_active) FROM push_subscriptions;")
print(f"  Total: {rows[0][0]}, Active FCM: {rows[0][1]}")

print("\n=== 4. Check notification_delivery_log ===")
rows = q("SELECT status, count(*), max(created_at)::text FROM notification_delivery_log WHERE channel='push' GROUP BY status;")
for r in rows: print(f"  {r[0]}: {r[1]} (latest: {r[2]})")
if not rows: print("  No push delivery logs")

print("\n=== 5. Check recent notifications with urgent priority ===")
rows = q("""
    SELECT n.id::text, n.title, n.priority, n.entity_type, n.created_at::text,
           (SELECT count(*) FROM notification_jobs j WHERE j.notification_id = n.id AND j.channel = 'push') as push_jobs
    FROM notifications n
    WHERE n.priority = 'urgent' OR n.entity_type = 'live_location_request'
    ORDER BY n.created_at DESC LIMIT 5;
""")
for r in rows:
    print(f"  {r[4]} | {r[1]} | priority={r[2]} | push_jobs={r[5]}")
if not rows: print("  No urgent notifications found")

print("\n=== 6. Check GUC settings ===")
rows = q("SELECT current_setting('app.settings.functions_base_url', true), current_setting('app.settings.cron_secret', true);")
base_url = rows[0][0] if rows else None
cron_sec = rows[0][1] if rows else None
print(f"  functions_base_url: {base_url or 'NOT SET'}")
print(f"  cron_secret: {'SET' if cron_sec else 'NOT SET'}")

print("\n=== 7. Try ALTER ROLE instead of ALTER DATABASE ===")
try:
    new_secret = secrets.token_urlsafe(32)
    cur.execute(f"ALTER ROLE postgres SET app.settings.functions_base_url = '{BASE}';")
    print(f"  functions_base_url: OK via ALTER ROLE")
    cur.execute(f"ALTER ROLE postgres SET app.settings.cron_secret = '{new_secret}';")
    print(f"  cron_secret: OK via ALTER ROLE [{len(new_secret)} chars]")
    # Save for later use
    with open("scripts/.new_cron_secret.tmp", "w") as f:
        f.write(new_secret)
    print(f"  Saved to scripts/.new_cron_secret.tmp")
except psycopg2.Error as e:
    print(f"  ALTER ROLE failed: {e}")
    print("  Trying via search_path trick...")
    try:
        cur.execute(f"SET app.settings.functions_base_url = '{BASE}';")
        print(f"  Session SET OK (not persistent)")
    except psycopg2.Error as e2:
        print(f"  Session SET also failed: {e2}")

# Verify after ALTER ROLE (need reconnect for role settings to take effect)
print("\n=== 8. Reconnecting to verify... ===")
cur.close()
conn.close()
conn = psycopg2.connect(DB, connect_timeout=15)
conn.autocommit = True
cur = conn.cursor()
rows = q("SELECT current_setting('app.settings.functions_base_url', true), length(current_setting('app.settings.cron_secret', true));")
if rows:
    print(f"  functions_base_url: {rows[0][0] or 'STILL NOT SET'}")
    print(f"  cron_secret length: {rows[0][1] or 'STILL NOT SET'}")

# Check if cron jobs need re-scheduling
print("\n=== 9. Re-schedule notification-dispatcher cron if needed ===")
try:
    base = q("SELECT current_setting('app.settings.functions_base_url', true);")[0][0]
    sec = q("SELECT current_setting('app.settings.cron_secret', true);")[0][0]
    if base and sec:
        headers = json.dumps({"Content-Type": "application/json", "x-cron-secret": sec})
        # Remove old job if exists
        try:
            q(f"SELECT cron.unschedule('hr_notification_dispatch');")
        except:
            conn.rollback()
        # Schedule new job
        cur.execute(f"""
            SELECT cron.schedule(
                'hr_notification_dispatch', '*/2 * * * *',
                format(
                    $job$ SELECT net.http_post(url := %L, headers := %L::jsonb, body := '{{}}'::jsonb) $job$,
                    '{base}/notification-dispatcher', '{headers}'::text
                )
            );
        """)
        print(f"  Scheduled hr_notification_dispatch every 2 minutes")
    else:
        print(f"  Cannot schedule: base={base}, secret={'SET' if sec else 'NOT SET'}")
except Exception as e:
    print(f"  Scheduling failed: {e}")

cur.close()
conn.close()
print("\nDone.")
