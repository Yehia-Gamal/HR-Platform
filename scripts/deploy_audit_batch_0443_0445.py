"""Smart idempotent deployer for the audit batch 0443-0445 to a remote Supabase project.

Flow:
  1) Inspect remote state (supabase_migrations.schema_migrations).
  2) Apply missing migrations in strict order (0443 -> 0444 -> 0445).
  3) Register each applied migration in schema_migrations (CLI-consistent).
  4) Post-verify: UTF-8 corruption check + RPC signature & privileges + pgrst reload.

Security:
  - Token read from SUPABASE_ACCESS_TOKEN env var only (never logged, never stored).
  - No PII printed anywhere.

Usage:
  python scripts/deploy_audit_batch_0443_0445.py            # normal idempotent run
  python scripts/deploy_audit_batch_0443_0445.py --force    # re-apply even if tracked
"""
import json, os, sys, urllib.request, urllib.error

PROJECT_REF = os.environ.get("SUPABASE_PROJECT_REF", "ujzzvqsodyhnnnpkoaml")
TOKEN = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
# يمكن تجاوز الـ endpoint بالكامل لأغراض الاختبار مقابل stack محلي متوافق.
API = os.environ.get("SUPABASE_QUERY_URL") or f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query"
MIGRATIONS_DIR = os.path.join(os.path.dirname(__file__), "..", "supabase", "migrations")

BROWSER_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)

BATCH = [
    ("0443", "deep_audit_phase1_hardening"),
    ("0444", "exclude_executive_from_attendance_and_lists"),
    ("0445", "grants_for_0444_functions_and_pgrst_reload"),
]


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


def run_query(sql):
    """POST SQL via Management API using UTF-8 bytes (safe for Arabic text)."""
    if not TOKEN:
        print("ERROR: set SUPABASE_ACCESS_TOKEN env var first.")
        sys.exit(2)
    data = json.dumps({"query": sql}).encode("utf-8")
    req = urllib.request.Request(API, data=data, method="POST", headers={
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json; charset=utf-8",
        "User-Agent": BROWSER_UA,
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return [{"__http_error__": True, "code": e.code, "body": body[:500]}]


def scalar(query_result, default=None):
    """Extract first column value of first row from query API result."""
    if isinstance(query_result, list) and query_result:
        row = query_result[0]
        if isinstance(row, dict):
            if "__http_error__" in row:
                return default
            return next(iter(row.values()), default)
        return row if not isinstance(row, (list, dict)) else default
    return default


def load_sql(version):
    path = None
    for name in os.listdir(MIGRATIONS_DIR):
        if name.startswith(version):
            path = os.path.join(MIGRATIONS_DIR, name)
            break
    if not path:
        fail(f"migration file starting with {version} not found locally")
    with open(path, "r", encoding="utf-8") as f:
        return f.read(), path


def sql_quote(text):
    """Escape a literal for embedding inside single quotes (CST on => safe)."""
    return "'" + text.replace("'", "''") + "'"


def main():
    force = "--force" in sys.argv
    print(f"Project ref: {PROJECT_REF}")

    # ── 1) Inspect remote tracking state ──────────────────────────────
    res = run_query("select version from supabase_migrations.schema_migrations where version in ('0443','0444','0445')")
    tracked = {r.get("version") for r in res} if isinstance(res, list) else set()
    print(f"Remote tracked versions in batch: {sorted(tracked) or 'none'}")

    todo = [v for v, _ in BATCH if force or v not in tracked]
    if not todo:
        print("Nothing to apply — batch already tracked remotely.")
    else:
        # ── 2) Apply missing migrations strictly in order ─────────────
        for version, name in BATCH:
            if version not in todo:
                continue
            sql, path = load_sql(version)
            print(f"Applying {version}_{name} ({len(sql)} chars)...", flush=True)
            out = run_query(sql)
            if isinstance(out, list) and out and isinstance(out[0], dict) and out[0].get("__http_error__"):
                fail(f"{version} failed: HTTP {out[0]['code']}: {out[0]['body']}")

            # ── 3) Track it so future CLI pushes stay consistent ──────
            track_sql = (
                "insert into supabase_migrations.schema_migrations(version, name, statements) "
                f"values ({sql_quote(version)}, {sql_quote(name)}, "
                f"array[{sql_quote(sql)}]::text[]) on conflict (version) do nothing;"
            )
            tout = run_query(track_sql)
            if isinstance(tout, list) and tout and isinstance(tout[0], dict) and tout[0].get("__http_error__"):
                fail(f"tracking insert failed for {version}: HTTP {tout[0]['code']}: {tout[0]['body']}")
            print(f"OK: {version} applied + tracked")

    # ── 4) Post-verification ──────────────────────────────────────────
    checks = []

    corrupted = scalar(run_query(
        r"select count(*)::int as c from pg_proc where prosrc ~ '\?\?\?'"), -1)
    checks.append(("UTF-8 corruption (must be 0)", corrupted == 0, corrupted))

    dash_ok = scalar(run_query(
        "select has_function_privilege('authenticated','public.get_attendance_dashboard(date,uuid,uuid,uuid)','execute')::bool"), False)
    checks.append(("authenticated can call get_attendance_dashboard", dash_ok is True, dash_ok))

    anon_denied = scalar(run_query(
        "select not has_function_privilege('anon','public.get_attendance_dashboard(date,uuid,uuid,uuid)','execute')::bool"), False)
    checks.append(("anon denied on get_attendance_dashboard", anon_denied is True, anon_denied))

    helper_ok = scalar(run_query(
        "select has_function_privilege('authenticated','public.is_employee_executive(uuid)','execute')::bool"), False)
    checks.append(("authenticated can call is_employee_executive (invoker dep)", helper_ok is True, helper_ok))

    exec_today_ok = scalar(run_query(
        "select has_function_privilege('authenticated','public.get_executive_attendance_today(text,uuid,text)','execute')::bool"), False)
    checks.append(("authenticated can call get_executive_attendance_today(text,uuid,text)", exec_today_ok is True, exec_today_ok))

    run_query("notify pgrst, 'reload schema';")
    checks.append(("pgrst schema cache reload notified", True, "sent"))

    print("\n── Verification ──")
    all_ok = True
    for label, ok, detail in checks:
        mark = "PASS" if ok else "FAIL"
        if not ok:
            all_ok = False
        print(f"[{mark}] {label}  (value={detail})")

    if all_ok:
        print("\nSUCCESS: batch deployed and verified.")
        sys.exit(0)
    fail("one or more verification checks failed")


if __name__ == "__main__":
    main()
