"""Generic idempotent deployer for any migration range to a remote Supabase project.

Replaces per-batch scripts: give it a range, it inspects remote tracking,
applies only what is missing (in strict ascending order), registers every
applied migration, then runs the standard post-verify suite.

Safety:
  - Token from SUPABASE_ACCESS_TOKEN env var only (never logged/stored).
  - Idempotent: tracked versions are skipped unless --force.
  - No PII printed anywhere.

Usage:
  python scripts/deploy_migrations.py --from 0443 [--to 0453] [--force]

Examples:
  SUPABASE_ACCESS_TOKEN=... python scripts/deploy_migrations.py --from 0456
  SUPABASE_ACCESS_TOKEN=... python scripts/deploy_migrations.py --from 0443 --to 0454
"""
import argparse, json, os, sys, time, urllib.request, urllib.error

# كونسولات Windows قد تعمل بـ cp1252 — نضبط UTF-8 حتى لا تنهار الطباعة
# على رموز مثل ── والعربية.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except AttributeError:
    pass

PROJECT_REF = os.environ.get("SUPABASE_PROJECT_REF", "ujzzvqsodyhnnnpkoaml")
TOKEN = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
API = os.environ.get("SUPABASE_QUERY_URL") or (
    f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query"
)
MIGRATIONS_DIR = os.path.join(os.path.dirname(__file__), "..", "supabase", "migrations")

BROWSER_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


def q(sql, attempts=4):
    """POST SQL via Management API using UTF-8 bytes (Arabic-safe), with retry."""
    if not TOKEN:
        print("ERROR: set SUPABASE_ACCESS_TOKEN env var first.")
        sys.exit(2)
    for attempt in range(attempts):
        try:
            data = json.dumps({"query": sql}).encode("utf-8")
            req = urllib.request.Request(API, data=data, method="POST", headers={
                "Authorization": f"Bearer {TOKEN}",
                "Content-Type": "application/json; charset=utf-8",
                "User-Agent": BROWSER_UA,
                "Accept": "application/json",
            })
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            return [{"__http_error__": True, "code": e.code, "body": body[:500]}]
        except OSError as e:
            wait = 5 * (attempt + 1)
            print(f"network error ({e}); retry {attempt+1}/{attempts} in {wait}s...", flush=True)
            time.sleep(wait)
    fail("network unreachable after retries")


def scalar(result, default=None):
    if isinstance(result, list) and result and isinstance(result[0], dict):
        row = result[0]
        if "__http_error__" in row:
            return default
        return next(iter(row.values()), default)
    return default


def load_sql(version):
    for name in sorted(os.listdir(MIGRATIONS_DIR)):
        if name.startswith(version):
            path = os.path.join(MIGRATIONS_DIR, name)
            with open(path, "r", encoding="utf-8") as f:
                return f.read(), path
    fail(f"no local file starts with version {version}")


def sql_quote(text):
    return "'" + text.replace("'", "''") + "'"


def main():
    parser = argparse.ArgumentParser(description="Deploy a migration range idempotently.")
    parser.add_argument("--from", dest="v_from", required=True, help="first version, e.g. 0456")
    parser.add_argument("--to", dest="v_to", default=None, help="last version (default = --from)")
    parser.add_argument("--force", action="store_true", help="re-apply even if tracked")
    args = parser.parse_args()

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
    print(f"Local range requested : {versions[0]} .. {versions[-1]} ({len(versions)} files)")

    res = q(
        "select version from supabase_migrations.schema_migrations "
        f"where version between '{v_from}' and '{v_to}'"
    )
    if isinstance(res, list) and res and isinstance(res[0], dict) and res[0].get("__http_error__"):
        fail(f"tracking inspection failed: HTTP {res[0]['code']}: {res[0]['body']}")
    tracked = {r.get("version") for r in res}
    print(f"Remote tracked in range: {sorted(tracked) or 'none'}")

    todo = [v for v in versions if args.force or v not in tracked]
    if not todo:
        print("Nothing to apply — range already fully tracked.")
    else:
        for version in todo:
            sql, path = load_sql(version)
            name = os.path.basename(path)[5:]
            print(f"Applying {version}_{name} ({len(sql)} chars)...", flush=True)
            out = q(sql)
            if isinstance(out, list) and out and isinstance(out[0], dict) and out[0].get("__http_error__"):
                fail(f"{version} failed: HTTP {out[0]['code']}: {out[0]['body']}")
            track_sql = (
                "insert into supabase_migrations.schema_migrations(version, name, statements) "
                f"values ({sql_quote(version)}, {sql_quote(name)}, "
                f"array[{sql_quote(sql)}]::text[]) on conflict (version) do nothing;"
            )
            tout = q(track_sql)
            if isinstance(tout, list) and tout and isinstance(tout[0], dict) and tout[0].get("__http_error__"):
                fail(f"tracking insert failed for {version}: HTTP {tout[0]['code']}")
            print(f"OK: {version} applied + tracked")

    # ── Post-verification ──────────────────────────────────────────────
    checks = []
    corrupted = scalar(q(r"select count(*)::int as c from pg_proc where prosrc ~ '\?\?\?'"), -1)
    checks.append(("UTF-8 corruption (must be 0)", corrupted == 0, corrupted))

    last_applied = todo[-1] if todo else None
    if last_applied:
        ok = scalar(q(
            "select exists("
            " select 1 from supabase_migrations.schema_migrations where version = '"
            + last_applied + "')"), False)
        checks.append((f"{last_applied} tracked remotely", ok is True, ok))

    q("notify pgrst, 'reload schema';")
    checks.append(("pgrst schema cache reload notified", True, "sent"))

    print("\n── Verification ──")
    all_ok = True
    for label, ok, detail in checks:
        mark = "PASS" if ok else "FAIL"
        if not ok:
            all_ok = False
        print(f"[{mark}] {label}  (value={detail})")

    if all_ok:
        print("\nSUCCESS: deployment verified.")
        sys.exit(0)
    fail("one or more verification checks failed")


if __name__ == "__main__":
    main()
