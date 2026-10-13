#!/bin/bash
# Test the real launcher/JVM, not only a shell surrogate.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMAGE="${1:?Usage: image-trino-lifecycle.sh IMAGE}"
TMP_DIR=$(mktemp -d)
TEST_IMAGE="trino-lifecycle-test:$(date +%s)-$$"
CID=""

cleanup() {
    if [[ -n "$CID" ]]; then docker rm -f "$CID" >/dev/null 2>&1 || true; fi
    docker image rm "$TEST_IMAGE" >/dev/null 2>&1 || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
    if [[ -n "$CID" ]]; then docker logs "$CID" --tail 100 >&2 || true; fi
    echo "not ok - $*" >&2
    exit 1
}

exec_with_timeout() {
    local seconds="$1"
    shift
    timeout --kill-after=2 "$((seconds + 10))" docker exec -i "$CID" \
        timeout --kill-after=2 "$seconds" "$@"
}

query() {
    exec_with_timeout 20 trino-cli --server http://127.0.0.1:8080 \
        --output-format TSV --execute "$1"
}

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wait-for-server.sh"

check_sql() {
    local output
    output=$(query 'SELECT 1 + 1') || fail "constant SQL query failed"
    [[ "$output" == 2 ]] || fail "unexpected constant SQL result: $output"
    output=$(query 'SELECT count(*) FROM tpch.tiny.nation') || fail "TPCH query failed"
    [[ "$output" == 25 ]] || fail "unexpected query result: $output"
}

test_cli_deadlines() {
    local mode pid rc expected
    for mode in normal ignore-term; do
        rc=0
        pid=$(exec_with_timeout 1 bash -c '
            if [[ "$1" == ignore-term ]]; then trap "" TERM; fi
            echo $$
            exec sleep 60
        ' bash "$mode") || rc=$?
        expected=124
        if [[ "$mode" == ignore-term ]]; then expected=137; fi
        [[ "$rc" == "$expected" && "$pid" =~ ^[0-9]+$ ]] || fail "CLI deadline failed ($mode, status $rc)"
        docker exec "$CID" bash -c '! kill -0 "$1" 2>/dev/null' bash "$pid" || fail "timed-out CLI remained running ($mode)"
    done
    echo 'ok - container CLI deadlines terminate normal and SIGTERM-ignoring commands'
}

stop_and_check() {
    local expected_runs="$1" output rc
    docker stop -t 40 "$CID" >/dev/null || fail "docker stop failed"
    rc=$(docker inspect -f '{{.State.ExitCode}}' "$CID")
    # The real Trino JVM may exit cleanly or report its SIGTERM status.
    [[ "$rc" == 0 || "$rc" == 143 ]] || fail "unexpected shutdown status $rc"
    output=$(docker logs "$CID" 2>&1)
    [[ "$(grep -c '^TEST_TRINO_PRE_READY$' <<< "$output")" == "$expected_runs" ]] || fail "pre-hooks did not run once per start"
    [[ "$(grep -c '^TEST_TRINO_POST_DONE$' <<< "$output")" == "$expected_runs" ]] || fail "post-hooks did not finish once per shutdown"
    if grep -Eq 'Main process did not exit|post-script: .*failed|Trino JVM is still running' <<< "$output"; then
        fail "Trino shutdown required escalation or post-hooks failed"
    fi
}

cp -R "${SCRIPT_DIR}/fixtures/etc" "$TMP_DIR/etc"
cp "${SCRIPT_DIR}/fixtures/10-prepare.sh" "$TMP_DIR/10-pre.sh"
cp "${SCRIPT_DIR}/fixtures/10-check-stopped.sh" "$TMP_DIR/10-post.sh"
cat > "$TMP_DIR/Dockerfile" <<EOF
FROM ${IMAGE}
USER root
COPY --chown=kubedoop:kubedoop etc/ /kubedoop/trino-server/etc/
COPY --chown=root:root --chmod=0755 10-pre.sh /kubedoop/mount/pre-script/10-prepare.sh
COPY --chown=root:root --chmod=0755 10-post.sh /kubedoop/mount/post-script/10-check-stopped.sh
USER kubedoop
EOF
docker build -q -t "$TEST_IMAGE" "$TMP_DIR" >/dev/null || fail "failed to build Trino test image"
# No command override: exercise the production default launcher run CMD.
CID=$(docker run -d "$TEST_IMAGE") || fail "failed to start Trino"
wait_for_server
test_cli_deadlines
check_sql
identity_before=$(docker exec "$CID" sha256sum /kubedoop/trino-server/etc/node.properties)
stop_and_check 1
docker start "$CID" >/dev/null || fail "failed to restart Trino"
wait_for_server
check_sql
identity_after=$(docker exec "$CID" sha256sum /kubedoop/trino-server/etc/node.properties)
[[ "$identity_after" == "$identity_before" ]] || fail "restart changed the configured node identity"
stop_and_check 2
echo 'ok - Trino default CMD serves SQL, stops gracefully, and restarts with unchanged node configuration'
