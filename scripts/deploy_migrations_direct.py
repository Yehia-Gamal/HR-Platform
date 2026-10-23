"""Direct PostgreSQL migration deployer for Supabase via pooler connection.

Used when the Management API access token is invalid or pooler direct connection
is available. Uses psycopg2 to connect directly to the Postgres instance.

Safety:
  - Password from SUPABASE_DB_PASSWORD env var only (never logged/stored).
  - Idempotent: tracked versions are skipped unless --force.
  - Transactions: each migration is committed with its schema_migrations record.

Usage:
  SUPABASE_DB_PASSWORD=... python scripts/deploy_migrations_direct.py --from 0700 [--to 0707] [--force]
"""
import argparse
import os
import sys
import psycopg2

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except AttributeError:
    pass

PROJECT_REF = os.environ.get("SUPABASE_PROJECT_REF", "ujzzvqsodyhnnnpkoaml")
DB_HOST = os.environ.get("SUPABASE_DB_HOST", "aws-1-eu-west-2.pooler.supabase.com")
DB_PORT = int(os.environ.get("SUPABASE_DB_PORT", "5432"))
DB_USER = os.environ.get("SUPABASE_DB_USER", f"postgres.{PROJECT_REF}")
DB_NAME = os.environ.get("SUPABASE_DB_NAME", "postgres")
DB_PASSWORD = os.environ.get("SUPABASE_DB_PASSWORD") or os.environ.get("PGPASSWORD", "")

MIGRATIONS_DIR = os.path.join(os.path.dirname(__file__), "..", "supabase", "migrations")


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


def load_sql(version):
    for name in sorted(os.listdir(MIGRATIONS_DIR)):
        if name.startswith(version) and name.endswith(".sql"):
            path = os.path.join(MIGRATIONS_DIR, name)
            with open(path, "r", encoding="utf-8") as f:
                return f.read(), path
    fail(f"no local file starts with version {version}")


def main():
    parser = argparse.ArgumentParser(description="Deploy migrations directly to Supabase via Postgres connection.")
    parser.add_argument("--from", dest="v_from", required=True, help="first version, e.g. 0700")
    parser.add_argument("--to", dest="v_to", default=None, help="last version (default = --from)")
    parser.add_argument("--force", action="store_true", help="re-apply even if tracked")
    args = parser.parse_args()

    if not DB_PASSWORD:
        fail("Set SUPABASE_DB_PASSWORD or PGPASSWORD environment variable first.")

    v_from, v_to = args.v_from.zfill(4), (args.v_to or args.v_from).zfill(4)
    if v_to < v_from:
        fail("--to must be >= --from")

    versions = [
        name[:4]
        for name in sorted(os.listdir(MIGRATIONS_DIR))
        if name.endswith(".sql") and v_from <= name[:4] <= v_to
    ]
    if not versions:
        fail(f"no migration files found between {v_from} and {v_to}")

    print(f"Project ref: {PROJECT_REF}")
    print(f"Connecting to: {DB_HOST}:{DB_PORT} as {DB_USER}...")
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            dbname=DB_NAME,
            sslmode="require",
            connect_timeout=15,
        )
        conn.autocommit = False
    except Exception as e:
        fail(f"database connection failed: {e}")

    cur = conn.cursor()
    cur.execute("SELECT version();")
    print(f"Database version: {cur.fetchone()[0]}")

    print(f"Local range requested : {versions[0]} .. {versions[-1]} ({len(versions)} files)")

    cur.execute(
        "select version from supabase_migrations.schema_migrations "
        "where version between %s and %s",
        (v_from, v_to),
    )
    tracked = {row[0] for row in cur.fetchall()}
    print(f"Remote tracked in range: {sorted(tracked) or 'none'}")

    todo = [v for v in versions if args.force or v not in tracked]
    if not todo:
        print("Nothing to apply — range already fully tracked.")
    else:
        for version in todo:
            sql, path = load_sql(version)
            name = os.path.basename(path)[5:]
            print(f"Applying {version}_{name} ({len(sql)} chars)...", flush=True)
            try:
                cur.execute(sql)
                cur.execute(
                    "insert into supabase_migrations.schema_migrations(version, name, statements) "
                    "values (%s, %s, array[%s]::text[]) on conflict (version) do nothing;",
                    (version, name, sql),
                )
                conn.commit()
                print(f"OK: {version} applied + tracked successfully.")
            except Exception as e:
                conn.rollback()
                fail(f"Migration {version} failed: {e}")

    # ── Post-verification ──────────────────────────────────────────────
    checks = []
    cur.execute(r"select count(*)::int from pg_proc where prosrc ~ '\?\?\?'")
    corrupted = cur.fetchone()[0]
    checks.append(("UTF-8 corruption (must be 0)", corrupted == 0, corrupted))

    cur.execute(
        "select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
        "where n.nspname = 'public' and p.prosrc ~ '(Ø|Ù|ðŸ|â€)'"
    )
    mojibake = cur.fetchone()[0]
    checks.append(("cp1252 mojibake in functions (must be 0)", mojibake == 0, mojibake))

    cur.execute(
        "select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace "
        "where n.nspname = 'public' and c.relkind in ('v','m') "
        "and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('authenticated', c.oid, 'SELECT')) "
        "and (c.relkind = 'm' or coalesce((select option_value from pg_options_to_table(c.reloptions) "
        "where option_name = 'security_invoker'), 'false') not in ('true','on'))"
    )
    exposed = cur.fetchone()[0]
    checks.append(("RLS-bypassing views readable by anon/authenticated (must be 0)", exposed == 0, exposed))

    cur.execute("select version from supabase_migrations.schema_migrations")
    all_tracked = {r[0] for r in cur.fetchall() if r[0]}
    max_tracked = max((v for v in all_tracked if v.isdigit()), default="0000")
    local = {n[:4] for n in os.listdir(MIGRATIONS_DIR) if n.endswith(".sql") and n[:4].isdigit()}
    untracked_gap = sorted(v for v in local if v < max_tracked and v not in all_tracked)
    checks.append(("untracked local migrations below remote max (must be none)",
                   not untracked_gap, ",".join(untracked_gap[:10]) or "none"))

    last_applied = todo[-1] if todo else None
    if last_applied:
        cur.execute("select exists(select 1 from supabase_migrations.schema_migrations where version = %s)", (last_applied,))
        ok = cur.fetchone()[0]
        checks.append((f"{last_applied} tracked remotely", ok is True, ok))

    # Notify PostgREST to reload schema
    cur.execute("notify pgrst, 'reload schema';")
    conn.commit()
    checks.append(("pgrst schema cache reload notified", True, "sent"))

    print("\n── Verification ──")
    all_ok = True
    for label, ok, detail in checks:
        mark = "PASS" if ok else "FAIL"
        if not ok:
            all_ok = False
        print(f"[{mark}] {label}  (value={detail})")

    cur.close()
    conn.close()

    if all_ok:
        print("\nSUCCESS: All migrations applied and verified successfully.")
        sys.exit(0)
    fail("one or more verification checks failed")


if __name__ == "__main__":
    main()
