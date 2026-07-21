#!/usr/bin/env bash
set -euo pipefail

: "${CONFIRM_STAGING:?Set CONFIRM_STAGING=YES after confirming this is not Production}"
: "${STAGING_PROJECT_REF:?Set STAGING_PROJECT_REF}"
: "${VITE_SUPABASE_URL:?Set VITE_SUPABASE_URL}"
: "${VITE_SUPABASE_PUBLISHABLE_KEY:?Set VITE_SUPABASE_PUBLISHABLE_KEY}"
VITE_APP_VERSION="${VITE_APP_VERSION:-0.10.0}"
VITE_APP_BUILD="${VITE_APP_BUILD:-10}"
VITE_APP_ENVIRONMENT="${VITE_APP_ENVIRONMENT:-staging}"
export VITE_APP_VERSION VITE_APP_BUILD VITE_APP_ENVIRONMENT

if [[ "$CONFIRM_STAGING" != "YES" ]]; then
  echo "Refusing deployment: CONFIRM_STAGING must equal YES." >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

npm ci
npm run check:all
npx supabase link --project-ref "$STAGING_PROJECT_REF"
npx supabase db push

for directory in supabase/functions/*; do
  [[ -d "$directory" ]] || continue
  name="$(basename "$directory")"
  [[ "$name" == "_shared" ]] && continue
  npx supabase functions deploy "$name" --project-ref "$STAGING_PROJECT_REF"
done

VITE_ENABLE_DEV_MOCKS=false npm run build

echo "Staging source deployment completed. Configure cron invocations and run persona/device smoke tests before approval."
