#!/bin/bash
# Smoke test of an image: starts a container and checks the configuration, the helpers and the initialization.
#
#   ./test.sh IMAGE [EXPECTED_RT_VERSION]
#
# Example: ./test.sh request-tracker:6.0.4 6.0.4

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 IMAGE [EXPECTED_RT_VERSION]" >&2
  exit 2
fi

image=$1
expected_version=${2:-}
port=${TEST_PORT:-8090}
name="rt-test-$$"
url="http://localhost:${port}/REST/2.0"
init_dir=$(mktemp -d)

cleanup() {
  docker rm -f "$name" > /dev/null 2>&1 || true
  rm -rf "$init_dir"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  docker logs --tail 50 "$name" >&2 || true
  exit 1
}

ok() {
  echo "ok: $*"
}

# returns the HTTP status code of a GET request; further arguments are passed to curl
status() {
  local path=$1
  shift
  curl -s -o /dev/null -w '%{http_code}' "$@" "${url}/${path}"
}

wait_healthy() {
  local health
  for _ in $(seq 120); do
    health=$(docker inspect --format '{{.State.Health.Status}}' "$name")
    [[ "$health" == healthy ]] && return 0
    [[ "$(docker inspect --format '{{.State.Running}}' "$name")" == true ]] || fail "container stopped"
    sleep 1
  done
  fail "container not healthy: $health"
}

# initial data and a script which are applied on the first start only
cat > "$init_dir/10-data.pl" <<'EOF'
@Users = ({ Name => 'alice', Password => 'alice-password', EmailAddress => 'alice@example.com', Privileged => 1 });
@CustomFields = ({ Name => 'Test Field', Type => 'FreeformSingle', LookupType => 'RT::Queue-RT::Ticket', Queue => ['General'] });
1;
EOF
cat > "$init_dir/20-script.sh" <<'EOF'
echo started >> /opt/rt/var/init-script-runs
EOF
echo "ignored" > "$init_dir/30-ignored.txt"
chmod -R a+rX "$init_dir"

docker run -d --name "$name" -p "${port}:${port}" \
  -e RT_WEB_PORT="$port" -e RT_ROOT_PASSWORD='new password' \
  -v "$init_dir:/docker-entrypoint-init.d:ro" "$image" > /dev/null
wait_healthy
ok "container is healthy"

[[ "$(status rt -u 'root:new password')" == 200 ]] || fail "login with RT_ROOT_PASSWORD"
[[ "$(status rt -u root:password)" == 401 ]] || fail "login with the old root password"
ok "RT_ROOT_PASSWORD"

version=$(curl -fsS -u 'root:new password' "${url}/rt" | sed -n 's/.*"Version" *: *"\([^"]*\)".*/\1/p')
if [[ -n "$expected_version" ]]; then
  [[ "$version" == "$expected_version" ]] || fail "RT version $version, expected $expected_version"
fi
ok "RT version $version"

# RT builds the URLs in responses from RT_WEB_DOMAIN and RT_WEB_PORT
curl -fsS -u 'root:new password' "${url}/queue/1" | grep -q "\"http://localhost:${port}/REST/2.0/queue/1\"" || fail "URLs use RT_WEB_PORT"
ok "RT_WEB_PORT"

token=$(docker exec "$name" rt-token)
[[ "$token" =~ ^[0-9]+-[0-9]+-[0-9a-f]{32}$ ]] || fail "rt-token printed: $token"
[[ "$(status rt -H "Authorization: token $token")" == 200 ]] || fail "login with token"
[[ "$(status rt -H "Authorization: token ${token%-*}-00000000000000000000000000000000")" == 401 ]] || fail "login with unknown token"
ok "rt-token"

# initial data: user and a custom field applied to the queue General
[[ "$(status user/alice -u alice:alice-password)" == 200 ]] || fail "user from initial data"
curl -fsS -H "Authorization: token $token" "${url}/queue/1?fields=TicketCustomFields" | grep -q '"Test Field"' \
  || fail "custom field from initial data applied to the queue"
[[ "$(docker exec "$name" cat /opt/rt/var/init-script-runs)" == started ]] || fail "init script"
ok "init directory"

docker exec "$name" rt-user bob --password bob-password --email bob@example.com > /dev/null
[[ "$(status user/bob -u bob:bob-password)" == 200 ]] || fail "rt-user created user"
[[ "$(status queue/1 -u bob:bob-password)" == 403 ]] || fail "user without rights"
docker exec "$name" rt-user bob --superuser > /dev/null
[[ "$(status queue/1 -u bob:bob-password)" == 200 ]] || fail "rt-user --superuser"
docker exec "$name" rt-user bob --no-superuser --password changed > /dev/null
[[ "$(status queue/1 -u bob:changed)" == 403 ]] || fail "rt-user --no-superuser and --password"
bob_token=$(docker exec "$name" rt-token --user bob --description test)
[[ "$(status user/bob -H "Authorization: token $bob_token")" == 200 ]] || fail "rt-token --user"
ok "rt-user"

echo '@Queues = ({ Name => "Support" }); 1;' | docker exec -i "$name" rt-initdata - > /dev/null
[[ "$(status queue/Support -H "Authorization: token $token")" == 200 ]] || fail "rt-initdata from stdin"
ok "rt-initdata"

secret_key=$(docker exec "$name" cat /opt/rt/var/secret-key)
[[ ${#secret_key} -ge 32 ]] || fail "secret key created"

# a restart keeps the data, applies the configuration again and does not initialize again
docker restart "$name" > /dev/null
wait_healthy
[[ "$(status user/alice -u alice:alice-password)" == 200 ]] || fail "data kept after restart"
[[ "$(docker exec "$name" cat /opt/rt/var/init-script-runs)" == started ]] || fail "init script ran again after restart"
[[ "$(status rt -H "Authorization: token $token")" == 200 ]] || fail "token kept after restart"
[[ "$(docker exec "$name" cat /opt/rt/var/secret-key)" == "$secret_key" ]] || fail "secret key kept after restart"
ok "restart"

if docker logs "$name" 2>&1 | grep -q "SecretKey is empty"; then
  fail "RT warns about the SecretKey"
fi
ok "SecretKey"

echo "all tests passed"
