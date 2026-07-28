#!/usr/bin/env bash
# Temporary build helper — reads signing creds from keystore.properties
# and passes them as env vars to flutter build. Delete after use.
set -euo pipefail
cd "$(dirname "$0")"

# Source keystore.properties (KEY=VALUE format)
while IFS='=' read -r key value; do
  [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
  export "$key"="$value"
done < android/keystore.properties

flutter build apk --release \
  --obfuscate \
  --split-debug-info=build/debug-info \
  --dart-define=SUPABASE_URL=https://ujzzvqsodyhnnnpkoaml.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_Q5JTOX-mLp5Y9wmxlZyTnQ_QBu5wPC2
