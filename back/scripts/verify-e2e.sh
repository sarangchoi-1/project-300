#!/usr/bin/env bash
#
# End-to-end verification of the Backend 1 auth foundation against the real local
# Supabase stack: real Supabase Auth over HTTP, real JWTs, real PostgREST, real
# RLS. This exercises the paths that back/scripts/verify-local.sh cannot, most
# importantly whether the auth.users signup trigger fires correctly when the
# insert comes from Supabase Auth (running as supabase_auth_admin) rather than
# from a superuser psql session.
#
# Prerequisites:  a Docker runtime, then `cd back && supabase start`.
# Usage:          back/scripts/verify-e2e.sh
#
# Keys are read from `supabase status` at runtime, so nothing secret is stored
# here. (The local stack's keys are fixed demo values anyway - they are NOT
# usable against a hosted project.)
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${BACK_DIR}"

FAILURES=0
pass() { printf '    ok    %s\n' "$1"; }
fail() { printf '    FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

check() { # check <description> <actual> <expected>
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi
}

echo "==> reading local stack configuration"
STATUS="$(supabase status -o env 2>/dev/null)" || { echo "supabase start first"; exit 1; }
eval "${STATUS}"
API_URL="${API_URL%\"}"; API_URL="${API_URL#\"}"
ANON_KEY="${ANON_KEY%\"}"; ANON_KEY="${ANON_KEY#\"}"
SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY%\"}"; SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY#\"}"
DB_URL="${DB_URL%\"}"; DB_URL="${DB_URL#\"}"
echo "    API_URL=${API_URL}"

# Unique suffix so the script can be re-run without colliding on email.
RUN="$(date +%s)"

# --- helpers ------------------------------------------------------------------

signup() { # signup <email> <password> <json-metadata> -> access_token (or empty)
  curl -sS -X POST "${API_URL}/auth/v1/signup" \
    -H "apikey: ${ANON_KEY}" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\",\"data\":$3}" \
    | jq -r '.access_token // empty'
}

signin() { # signin <email> <password> -> access_token
  curl -sS -X POST "${API_URL}/auth/v1/token?grant_type=password" \
    -H "apikey: ${ANON_KEY}" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" \
    | jq -r '.access_token // empty'
}

rest_get() { # rest_get <token> <path-and-query> -> body
  curl -sS "${API_URL}/rest/v1/$1" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer $2"
}

rest_code() { # rest_code <method> <token> <path> <body> -> http status
  curl -sS -o /dev/null -w '%{http_code}' -X "$1" "${API_URL}/rest/v1/$3" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer $2" \
    -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
    ${4:+-d "$4"}
}

rest_patch_count() { # rest_patch_count <token> <path> <body> -> number of rows changed
  curl -sS -X PATCH "${API_URL}/rest/v1/$2" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer $1" \
    -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
    -d "$3" | jq 'if type=="array" then length else 0 end'
}

sql() { psql --no-psqlrc -q -tAc "$1" "${DB_URL}"; }

# ------------------------------------------------------------------------------
echo ""
echo "### 1. signup through real Supabase Auth fires the profile trigger"
# ------------------------------------------------------------------------------

ADMIN_EMAIL="e2e-admin-${RUN}@example.test"
MEMBER_EMAIL="e2e-member-${RUN}@example.test"
EVIL_EMAIL="e2e-evil-${RUN}@example.test"
PW='correct-horse-battery-staple-1'

ADMIN_TOKEN="$(signup "${ADMIN_EMAIL}"  "${PW}" '{"display_name":"E2E Admin"}')"
MEMBER_TOKEN="$(signup "${MEMBER_EMAIL}" "${PW}" '{"display_name":"E2E Member"}')"
# Hostile metadata: try to self-assign admin + approved at signup time.
EVIL_TOKEN="$(signup "${EVIL_EMAIL}" "${PW}" \
  '{"display_name":"E2E Evil","role":"admin","approval_status":"approved"}')"

[[ -n "${ADMIN_TOKEN}" && -n "${MEMBER_TOKEN}" && -n "${EVIL_TOKEN}" ]] \
  && pass "three users signed up and received sessions" \
  || fail "signup did not return a session (is enable_confirmations on?)"

check "a profile row exists for every new auth user" \
  "$(sql "select count(*) from public.profiles p join auth.users u on u.id=p.id where u.email like 'e2e-%-${RUN}@example.test'")" \
  "3"

check "display_name came from client metadata" \
  "$(sql "select display_name from public.profiles where id=(select id from auth.users where email='${MEMBER_EMAIL}')")" \
  "E2E Member"

check "new profiles default to member/pending" \
  "$(sql "select count(*) from public.profiles p join auth.users u on u.id=p.id where u.email like 'e2e-%-${RUN}@example.test' and p.role='member' and p.approval_status='pending'")" \
  "3"

check "hostile signup metadata cannot self-assign admin/approved" \
  "$(sql "select role||'/'||approval_status from public.profiles where id=(select id from auth.users where email='${EVIL_EMAIL}')")" \
  "member/pending"

# ------------------------------------------------------------------------------
echo ""
echo "### 2. pending user over PostgREST"
# ------------------------------------------------------------------------------

check "a pending user reads exactly their own profile" \
  "$(rest_get "profiles?select=approval_status" "${MEMBER_TOKEN}" | jq 'length')" "1"
check "and sees approval_status=pending (drives the waiting screen)" \
  "$(rest_get "profiles?select=approval_status" "${MEMBER_TOKEN}" | jq -r '.[0].approval_status')" \
  "pending"
check "a pending user sees no groups" \
  "$(rest_get "groups?select=id" "${MEMBER_TOKEN}" | jq 'length')" "0"
check "a pending user sees no memberships" \
  "$(rest_get "group_members?select=id" "${MEMBER_TOKEN}" | jq 'length')" "0"
check "a pending user cannot approve themselves" \
  "$(rest_patch_count "${MEMBER_TOKEN}" "profiles?approval_status=eq.pending" '{"approval_status":"approved"}')" \
  "0"
check "a pending user cannot promote themselves" \
  "$(rest_patch_count "${MEMBER_TOKEN}" "profiles?role=eq.member" '{"role":"admin"}')" "0"

# ------------------------------------------------------------------------------
echo ""
echo "### 3. unauthenticated (anon key only)"
# ------------------------------------------------------------------------------

ANON_CODE="$(curl -sS -o /dev/null -w '%{http_code}' \
  "${API_URL}/rest/v1/profiles?select=id" -H "apikey: ${ANON_KEY}")"
[[ "${ANON_CODE}" == "401" || "${ANON_CODE}" == "403" ]] \
  && pass "anon is refused on profiles (HTTP ${ANON_CODE})" \
  || fail "anon got HTTP ${ANON_CODE} on profiles, expected 401/403"

# ------------------------------------------------------------------------------
echo ""
echo "### 4. bootstrap_first_admin is unreachable from clients"
# ------------------------------------------------------------------------------

USER_RPC="$(rest_code POST "${MEMBER_TOKEN}" "rpc/bootstrap_first_admin" \
  "{\"p_email\":\"${MEMBER_EMAIL}\"}")"
[[ "${USER_RPC}" == "404" || "${USER_RPC}" == "401" || "${USER_RPC}" == "403" ]] \
  && pass "an authenticated user cannot RPC bootstrap_first_admin (HTTP ${USER_RPC})" \
  || fail "authenticated RPC returned HTTP ${USER_RPC}, expected 401/403/404"

SR_RPC="$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
  "${API_URL}/rest/v1/rpc/bootstrap_first_admin" \
  -H "apikey: ${SERVICE_ROLE_KEY}" -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  -H 'Content-Type: application/json' -d "{\"p_email\":\"${MEMBER_EMAIL}\"}")"
[[ "${SR_RPC}" != "200" ]] \
  && pass "even the service_role key cannot RPC bootstrap_first_admin (HTTP ${SR_RPC})" \
  || fail "service_role successfully called bootstrap_first_admin - it must not be able to"

# Trusted path: the SQL Editor equivalent. The happy path is only observable on a
# database that has no admin yet, so re-runs check the refusal instead.
if [[ "$(sql "select count(*) from public.profiles where role='admin'")" == "0" ]]; then
  check "bootstrap promotes the first admin from a trusted SQL session" \
    "$(sql "select role||'/'||approval_status from public.bootstrap_first_admin('${ADMIN_EMAIL}')")" \
    "admin/approved"
  if sql "select 1 from public.bootstrap_first_admin('${MEMBER_EMAIL}')" >/dev/null 2>&1; then
    fail "bootstrap ran a second time - it must refuse once an admin exists"
  else
    pass "bootstrap refuses to run a second time"
  fi
else
  printf '    skip  bootstrap happy path (an admin already exists; `supabase db reset` to retest)\n'
  if sql "select 1 from public.bootstrap_first_admin('${ADMIN_EMAIL}')" >/dev/null 2>&1; then
    fail "bootstrap ran while an admin already exists - it must refuse"
  else
    pass "bootstrap refuses to run while an admin already exists"
  fi
  sql "update public.profiles set role='admin', approval_status='approved'
        where id=(select id from auth.users where email='${ADMIN_EMAIL}')" >/dev/null
  pass "promoted the test admin directly from a trusted SQL session"
fi

# ------------------------------------------------------------------------------
echo ""
echo "### 5. admin over PostgREST"
# ------------------------------------------------------------------------------

# Re-issue the token so it is minted after the promotion.
ADMIN_TOKEN="$(signin "${ADMIN_EMAIL}" "${PW}")"

check "is_admin() is true for the bootstrapped admin" \
  "$(curl -sS -X POST "${API_URL}/rest/v1/rpc/is_admin" \
      -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${ADMIN_TOKEN}")" "true"

TOTAL_PROFILES="$(sql "select count(*) from public.profiles")"
check "an admin reads every profile" \
  "$(rest_get "profiles?select=id" "${ADMIN_TOKEN}" | jq 'length')" "${TOTAL_PROFILES}"

MEMBER_ID="$(sql "select id from auth.users where email='${MEMBER_EMAIL}'")"

check "an admin can approve a pending user" \
  "$(rest_patch_count "${ADMIN_TOKEN}" "profiles?id=eq.${MEMBER_ID}" \
      '{"approval_status":"approved"}')" \
  "1"

GROUP_CODE="$(rest_code POST "${ADMIN_TOKEN}" "groups" \
  "{\"name\":\"E2E Group ${RUN}\",\"description\":\"created by verify-e2e\"}")"
check "an admin can create a group (HTTP 201)" "${GROUP_CODE}" "201"

GROUP_ID="$(sql "select id from public.groups where name='E2E Group ${RUN}'")"

MEMBERSHIP_CODE="$(rest_code POST "${ADMIN_TOKEN}" "group_members" \
  "{\"group_id\":\"${GROUP_ID}\",\"user_id\":\"${MEMBER_ID}\",\"role\":\"leader\"}")"
check "an admin can add a member and appoint them leader (HTTP 201)" "${MEMBERSHIP_CODE}" "201"

DUP_CODE="$(rest_code POST "${ADMIN_TOKEN}" "group_members" \
  "{\"group_id\":\"${GROUP_ID}\",\"user_id\":\"${MEMBER_ID}\"}")"
check "duplicate membership is rejected (HTTP 409)" "${DUP_CODE}" "409"

# ------------------------------------------------------------------------------
echo ""
echo "### 6. approved member / leader over PostgREST"
# ------------------------------------------------------------------------------

MEMBER_TOKEN="$(signin "${MEMBER_EMAIL}" "${PW}")"

check "an approved user now sees their own group" \
  "$(rest_get "groups?select=id,name" "${MEMBER_TOKEN}" | jq 'length')" "1"
check "and it is the right group" \
  "$(rest_get "groups?select=id" "${MEMBER_TOKEN}" | jq -r '.[0].id')" "${GROUP_ID}"
check "the group embed through group_members works" \
  "$(rest_get "group_members?select=role,groups(name)&is_active=eq.true" "${MEMBER_TOKEN}" \
      | jq -r '.[0].groups.name')" \
  "E2E Group ${RUN}"
check "is_group_leader() is true over RPC for the appointed leader" \
  "$(curl -sS -X POST "${API_URL}/rest/v1/rpc/is_group_leader" \
      -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${MEMBER_TOKEN}" \
      -H 'Content-Type: application/json' -d "{\"p_group_id\":\"${GROUP_ID}\"}")" \
  "true"
check "a leader still cannot change their own group role" \
  "$(rest_patch_count "${MEMBER_TOKEN}" "group_members?group_id=eq.${GROUP_ID}" '{"role":"member"}')" \
  "0"
check "a leader still cannot promote themselves to app admin" \
  "$(rest_patch_count "${MEMBER_TOKEN}" "profiles?id=eq.${MEMBER_ID}" '{"role":"admin"}')" "0"
check "a leader cannot create a group" \
  "$(rest_code POST "${MEMBER_TOKEN}" "groups" '{"name":"Leader Made This"}')" "403"

# ------------------------------------------------------------------------------
echo ""
if [[ ${FAILURES} -eq 0 ]]; then
  echo "ALL END-TO-END CHECKS PASSED"
else
  echo "${FAILURES} CHECK(S) FAILED"
  exit 1
fi
