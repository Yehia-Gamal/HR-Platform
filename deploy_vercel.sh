#!/usr/bin/env bash
# Temporary Vercel deploy helper — reads token from .vercel_token (gitignored).
# Delete both files after use.
set -euo pipefail
cd "$(dirname "$0")"
if [[ -f .vercel_token ]]; then
  export VERCEL_TOKEN
  VERCEL_TOKEN="$(cat .vercel_token)"
fi
: "${VERCEL_TOKEN:?Set VERCEL_TOKEN or create .vercel_token}"
npx vercel --prod --yes
