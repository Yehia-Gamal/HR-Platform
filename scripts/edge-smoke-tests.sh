#!/usr/bin/env bash
# Edge Functions runtime smoke tests (P0.5).
# Usage (local):
#   npx supabase start
#   npx supabase functions serve &   # or run each function individually
#   BASE_URL=http://127.0.0.1:54321/functions/v1 ANON_KEY=<anon> ./scripts/edge-smoke-tests.sh
#
# No secrets are printed. Each check asserts the *security* contract:
# unauthorized/invalid input must fail safely, never with a DB error leak.

set -u
BASE_URL="${BASE_URL:-http://127.0.0.1:54321/functions/v1}"
ANON_KEY="${ANON_KEY:-}"
PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3" body="$4"
  if [[ "$actual" == "$expected" ]]; then
    echo "ok - ${name} (HTTP ${actual})"
    PASS=$((PASS+1))
  else
    echo "not ok - ${name} (expected ${expected}, got ${actual}): ${body:0:200}"
    FAIL=$((FAIL+1))
  fi
  # Fail-safe leak check: response must not contain raw SQL/DB internals.
  if echo "$body" | grep -qiE 'syntax error|pg_|sqlstate|relation .* does not exist'; then
    echo "not ok - ${name}: response leaks database internals"
    FAIL=$((FAIL+1))
  fi
}

call() { # method path auth body -> sets HTTP_CODE, HTTP_BODY
  local method="$1" path="$2" auth="$3" body="$4" extra_header="${5:-}"
  local args=(-s -o /tmp/edge_body -w '%{http_code}' -X "$method" "${BASE_URL}/${path}" -H 'Content-Type: application/json')
  [[ -n "$auth" ]] && args+=(-H "Authorization: Bearer ${auth}")
  [[ -n "$ANON_KEY" ]] && args+=(-H "apikey: ${ANON_KEY}")
  [[ -n "$extra_header" ]] && args+=(-H "$extra_header")
  [[ -n "$body" ]] && args+=(-d "$body")
  HTTP_CODE=$(curl "${args[@]}")
  HTTP_BODY=$(cat /tmp/edge_body 2>/dev/null || echo '')
}

echo "# Edge smoke tests against ${BASE_URL}"
echo "# $(date -u +%FT%TZ)"

# ---- 1. identifier-sign-in ------------------------------------------------
call POST identifier-sign-in "" '{}'
check "identifier-sign-in rejects empty body" 400 "$HTTP_CODE" "$HTTP_BODY"

call POST identifier-sign-in "" '{"identifier":"nobody@nowhere.test","password":"wrong-password"}'
check "identifier-sign-in generic failure for unknown identifier" 401 "$HTTP_CODE" "$HTTP_BODY"
if echo "$HTTP_BODY" | grep -qiE 'not found|no user|exists'; then
  echo "not ok - identifier-sign-in leaks account existence"; FAIL=$((FAIL+1))
else
  echo "ok - identifier-sign-in does not leak account existence"; PASS=$((PASS+1))
fi

call GET identifier-sign-in "" ''
check "identifier-sign-in rejects GET" 405 "$HTTP_CODE" "$HTTP_BODY"

# ---- 2. admin-create-employee ----------------------------------------------
call POST admin-create-employee "" '{"fullNameAr":"x"}'
check "admin-create-employee rejects missing token" 401 "$HTTP_CODE" "$HTTP_BODY"

call POST admin-create-employee "invalid-token" '{"fullNameAr":"x"}'
check "admin-create-employee rejects invalid token" 401 "$HTTP_CODE" "$HTTP_BODY"

# ---- 3. webauthn-challenge --------------------------------------------------
call POST webauthn-challenge "" '{"purpose":"attendance"}'
check "webauthn-challenge rejects anonymous" 401 "$HTTP_CODE" "$HTTP_BODY"

# ---- 4. passkey-register ----------------------------------------------------
call POST passkey-register "" '{}'
check "passkey-register rejects anonymous" 401 "$HTTP_CODE" "$HTTP_BODY"

# ---- 5. verify-attendance-punch ----------------------------------------------
call POST verify-attendance-punch "" '{}'
check "verify-attendance-punch rejects anonymous" 401 "$HTTP_CODE" "$HTTP_BODY"

call POST verify-attendance-punch "invalid-token" '{"latitude":999}'
check "verify-attendance-punch rejects invalid token" 401 "$HTTP_CODE" "$HTTP_BODY"

# ---- 6-9. Cron-protected workers ---------------------------------------------
for fn in retention-cleanup notification-dispatcher integration-outbox-worker scheduled-report-runner; do
  call POST "$fn" "" '{}'
  check "${fn} rejects call without x-cron-secret" 401 "$HTTP_CODE" "$HTTP_BODY"

  call POST "$fn" "" '{}' 'x-cron-secret: wrong-secret-value'
  check "${fn} rejects wrong x-cron-secret" 401 "$HTTP_CODE" "$HTTP_BODY"

  call GET "$fn" "" ''
  # GET must never trigger work: 405 or 401 acceptable
  if [[ "$HTTP_CODE" == "405" || "$HTTP_CODE" == "401" ]]; then
    echo "ok - ${fn} rejects GET (HTTP ${HTTP_CODE})"; PASS=$((PASS+1))
  else
    echo "not ok - ${fn} accepted GET (HTTP ${HTTP_CODE})"; FAIL=$((FAIL+1))
  fi
done

# ---- CORS preflight (all deployable functions) --------------------------------
for fn in identifier-sign-in admin-create-employee webauthn-challenge passkey-register \
          verify-attendance-punch retention-cleanup notification-dispatcher \
          integration-outbox-worker scheduled-report-runner; do
  code=$(curl -s -o /tmp/edge_body -w '%{http_code}' -X OPTIONS "${BASE_URL}/${fn}" \
    -H 'Origin: https://evil.example.com' \
    -H 'Access-Control-Request-Method: POST')
  allow_origin=$(curl -s -D - -o /dev/null -X OPTIONS "${BASE_URL}/${fn}" \
    -H 'Origin: https://evil.example.com' \
    -H 'Access-Control-Request-Method: POST' | grep -i '^access-control-allow-origin:' | tr -d '\r' | cut -d' ' -f2)
  if [[ "$allow_origin" == "https://evil.example.com" ]]; then
    echo "not ok - ${fn} CORS reflects untrusted origin"; FAIL=$((FAIL+1))
  else
    echo "ok - ${fn} CORS does not reflect untrusted origin (allow-origin='${allow_origin:-<none>}')"; PASS=$((PASS+1))
  fi
done

echo
echo "# Summary: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] || exit 1
