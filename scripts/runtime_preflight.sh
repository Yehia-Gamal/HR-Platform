#!/usr/bin/env bash
set -euo pipefail
command -v node >/dev/null || { echo 'Node.js is required'; exit 1; }
command -v npm >/dev/null || { echo 'npm is required'; exit 1; }
[[ -f package-lock.json ]] || { echo 'package-lock.json missing'; exit 1; }
for key in VITE_SUPABASE_URL VITE_SUPABASE_PUBLISHABLE_KEY; do
  [[ -n "${!key:-}" ]] || echo "WARNING: $key is not set"
done
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  echo 'Docker ready: Supabase runtime tests can run.'
else
  echo 'WARNING: Docker unavailable; Supabase db reset/test cannot run locally.'
fi
if command -v flutter >/dev/null; then
  echo 'Flutter ready.'
else
  echo 'WARNING: Flutter SDK unavailable; use GitHub Flutter CI.'
fi
npm ci
npm run check:all
