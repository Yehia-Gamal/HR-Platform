#!/usr/bin/env bash
# Temporary Vercel deploy helper — delete after use.
set -euo pipefail
cd "$(dirname "$0")"
export VERCEL_TOKEN="${VERCEL_TOKEN:?Set VERCEL_TOKEN}"
npx vercel --prod --yes
