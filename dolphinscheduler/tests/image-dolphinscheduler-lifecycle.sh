#!/bin/bash
# Real standalone API/DB behavior, persisted restart and signal-driven shutdown.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMAGE="${1:?Usage: image-dolphinscheduler-lifecycle.sh IMAGE}"
TEST_IMAGE="dolphin-application-test:$(date +%s)-$$"
CID=""
SESSION=""
cleanup() {
    [[ -z "$CID" ]] || docker rm -f "$CID" >/dev/null 2>&1 || true
    docker image rm "$TEST_IMAGE" >/dev/null 2>&1 || true
}
trap cleanup EXIT
fail() { [[ -z "$CID" ]] || docker logs --tail 120 "$CID" >&2; echo "not ok - $*" >&2; exit 1; }
command -v jq >/dev/null || { echo 'jq is required on the test host' >&2; exit 1; }
api() {
    local path="$1"; shift
    timeout 15 docker exec "$CID" curl -fsS --connect-timeout 2 --max-time 8 \
        "http://127.0.0.1:12345/dolphinscheduler/$path" "$@"
}
login() {
    local response
    response=$(api login -X POST --data-urlencode userName=admin --data-urlencode userPassword=dolphinscheduler123) || return 1
    SESSION=$(jq -er 'select(.code==0) | .data.sessionId | select(type=="string" and length>0)' <<< "$response")
}
wait_ready() {
    local deadline=$((SECONDS + 240))
    while ((SECONDS < deadline)); do
        if login >/dev/null 2>&1; then return 0; fi
        [[ "$(docker inspect -f '{{.State.Running}}' "$CID")" == true ]] || fail 'standalone exited during startup'
        sleep 2
    done
    fail 'real API login never became ready'
}
check_jvm() {
    local pid
    pid=$(docker logs "$CID" 2>&1 | awk '/Main process started/ {gsub(/[()]/, ""); print $NF}' | tail -1)
    [[ "$pid" =~ ^[0-9]+$ ]] || fail 'managed PID missing'
    docker exec "$CID" bash -c '
        test "$(cat "/proc/$1/comm")" = java
        grep -aq org.apache.dolphinscheduler.StandaloneServer "/proc/$1/cmdline"
    ' bash "$pid" || fail 'launcher did not hand off managed PID to real standalone JVM'
}
stop_and_check() {
    local signal="$1" count="$2" rc logs
    if [[ "$signal" == TERM ]]; then
        docker stop -t 45 "$CID" >/dev/null
    else
        docker kill --signal INT "$CID" >/dev/null
        timeout 45 docker wait "$CID" >/dev/null || fail 'INT shutdown timed out'
    fi
    rc=$(docker inspect -f '{{.State.ExitCode}}' "$CID")
    [[ "$rc" == 0 || "$rc" == 143 ]] || fail "unexpected shutdown status $rc"
    logs=$(docker logs "$CID" 2>&1)
    [[ "$(grep -c '^TEST_DOLPHIN_PRE_READY$' <<< "$logs")" == "$count" ]] || fail 'pre-hook count changed'
    [[ "$(grep -c '^TEST_DOLPHIN_POST_DONE$' <<< "$logs")" == "$count" ]] || fail 'post-hook count changed'
    ! grep -Eq 'Main process did not exit|post-script: .*failed|standalone JVM is still running' <<< "$logs" || fail 'shutdown escalated or cleanup failed'
}
docker build -q --build-arg "IMAGE=$IMAGE" -t "$TEST_IMAGE" "$SCRIPT_DIR/fixtures" >/dev/null
# No command override: exercise production default CMD.
CID=$(docker run -d "$TEST_IMAGE")
wait_ready
check_jvm
response=$(api projects -X POST -H "sessionId: $SESSION" --data-urlencode projectName=universal_lifecycle --data-urlencode description=persisted_after_restart) || fail 'real project creation failed'
code=$(jq -er 'select(.code==0) | .data.code' <<< "$response") || fail 'project was not created'
stop_and_check TERM 1
docker start "$CID" >/dev/null
wait_ready
check_jvm
response=$(api "projects/$code" -H "sessionId: $SESSION") || fail 'project read after restart failed'
jq -e '(.code==0) and (.data.name=="universal_lifecycle") and (.data.description=="persisted_after_restart")' <<< "$response" >/dev/null || fail 'restart lost project identity/data'
stop_and_check INT 2
echo 'ok - default standalone CMD serves real login/project APIs, persists data across restart, and shuts down on TERM/INT'
