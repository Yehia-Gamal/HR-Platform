"""Apply a local migration SQL file to the remote Supabase project via the Management API.

Token is read from the SUPABASE_ACCESS_TOKEN environment variable so it never lives in the repo.
Usage:
  SUPABASE_ACCESS_TOKEN=... python scripts/apply_migration_remote.py <file.sql | "SELECT ...">
"""
import json, sys, os, urllib.request, urllib.error

PROJECT_REF = os.environ.get("SUPABASE_PROJECT_REF", "ujzzvqsodyhnnnpkoaml")
TOKEN = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
API = f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query"

BROWSER_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)


def run_query(sql):
    if not TOKEN:
        print("ERROR: set SUPABASE_ACCESS_TOKEN env var first.")
        sys.exit(2)
    data = json.dumps({"query": sql}).encode("utf-8")
    req = urllib.request.Request(API, data=data, method="POST", headers={
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json",
        "User-Agent": BROWSER_UA,
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print(f"HTTP {e.code}: {body}")
        raise


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python apply_migration_remote.py <migration_file_or_sql>")
        sys.exit(1)

    arg = sys.argv[1]
    if os.path.isfile(arg):
        with open(arg, "r", encoding="utf-8") as f:
            sql = f.read()
        print(f"Applying {arg} ({len(sql)} chars)...")
    else:
        sql = arg
        print(f"Running query ({len(sql)} chars)...")

    result = run_query(sql)
    print(json.dumps(result, indent=2, ensure_ascii=False))
