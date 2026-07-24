#!/usr/bin/env python3
"""Sets GUC + CRON_SECRET on staging Supabase project."""
import json, os, secrets, urllib.request, urllib.error

PROJECT = 'ujzzvqsodyhnnnpkoaml'
TOKEN = os.environ.get('SB_TOKEN', '')
BASE_URL = f'https://ujzzvqsodyhnnnpkoaml.supabase.co/functions/v1'
CRON_SECRET = secrets.token_urlsafe(32)

def api(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f'https://api.supabase.com/v1/projects/{PROJECT}/{path}',
        data=data,
        headers={
            'Authorization': f'Bearer {TOKEN}',
            'Content-Type': 'application/json',
        },
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return {'error': e.read().decode()[:300]}

# 1. Set GUC settings
print('Setting GUC app.settings.functions_base_url...')
r1 = api('database/query', {
    'query': f"ALTER DATABASE postgres SET app.settings.functions_base_url = '{BASE_URL}';"
})
print('  Result:', json.dumps(r1)[:200])

print('Setting GUC app.settings.cron_secret...')
r2 = api('database/query', {
    'query': f"ALTER DATABASE postgres SET app.settings.cron_secret = '{CRON_SECRET}';"
})
print('  Result:', json.dumps(r2)[:200])

# 2. Verify
print('Verifying...')
r3 = api('database/query', {
    'query': "SELECT current_setting('app.settings.functions_base_url', true) as url, length(current_setting('app.settings.cron_secret', true)) as sec_len"
})
print('  Verify:', json.dumps(r3))

# 3. Output the secret for supabase secrets set
print(f'\nCRON_SECRET={CRON_SECRET}')
print('Run: npx supabase secrets set CRON_SECRET=<above> --project-ref ujzzvqsodyhnnnpkoaml')
