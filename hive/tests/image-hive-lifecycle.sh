#!/bin/bash
# Real metastore Thrift operations and Derby persistence across process restart.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMAGE="${1:?Usage: image-hive-lifecycle.sh IMAGE}"
TEST_IMAGE="hive-lifecycle-test:$(date +%s)-$$"
CID=""
cleanup() {
    [[ -z "$CID" ]] || docker rm -f "$CID" >/dev/null 2>&1 || true
    docker image rm "$TEST_IMAGE" >/dev/null 2>&1 || true
}
trap cleanup EXIT
fail() {
    [[ -z "$CID" ]] || docker logs --tail 120 "$CID" >&2 || true
    echo "not ok - $*" >&2
    exit 1
}
client() {
    timeout --kill-after=2 25 docker exec "$CID" timeout --kill-after=2 15 bash -c '
        classpath="/kubedoop/run/client:$HIVE_HOME/lib/*:$HADOOP_HOME/share/hadoop/common/*:$HADOOP_HOME/share/hadoop/common/lib/*"
        exec java -cp "$classpath" MetastoreClient "$@"
    ' bash "$@"
}
wait_for_server() {
    local deadline=$((SECONDS + 180))
    while ((SECONDS < deadline)); do
        if client ready >/dev/null 2>&1; then return 0; fi
        [[ "$(docker inspect -f '{{.State.Running}}' "$CID")" == true ]] || fail "metastore exited during startup"
        sleep 2
    done
    client ready >&2 || true
    fail "metastore Thrift API did not become ready"
}
check_foreground_jvm() {
    local pid
    pid=$(docker logs "$CID" 2>&1 | awk '/Main process started/ {gsub(/[()]/, ""); print $NF}' | tail -1)
    [[ "$pid" =~ ^[0-9]+$ ]] || fail "managed main PID not reported"
    docker exec "$CID" bash -c '
        test "$(cat "/proc/$1/comm")" = java
        grep -aq org.apache.hadoop.hive.metastore.HiveMetaStore "/proc/$1/cmdline"
    ' bash "$pid" || fail "native launcher did not hand off the managed PID to the metastore JVM"
}
stop_and_check() {
    local count="$1" signal="$2" output rc
    if [[ "$signal" == TERM ]]; then
        docker stop -t 45 "$CID" >/dev/null || fail "docker stop failed"
    else
        docker kill --signal "$signal" "$CID" >/dev/null || fail "shutdown signal failed"
        timeout 45 docker wait "$CID" >/dev/null || fail "signal-driven shutdown did not finish"
    fi
    rc=$(docker inspect -f '{{.State.ExitCode}}' "$CID")
    [[ "$rc" == 0 || "$rc" == 143 ]] || fail "unexpected shutdown status $rc"
    output=$(docker logs "$CID" 2>&1)
    [[ "$(grep -c '^TEST_HIVE_PRE_READY$' <<< "$output")" == "$count" ]] || fail "pre-hooks did not run once per start"
    [[ "$(grep -c '^TEST_HIVE_POST_DONE$' <<< "$output")" == "$count" ]] || fail "post-hooks did not run once per stop"
    ! grep -Eq 'Main process did not exit|post-script: .*failed|metastore JVM is still running' <<< "$output" || fail "shutdown escalated or post-hooks failed"
}
docker build -q --build-arg "IMAGE=$IMAGE" -t "$TEST_IMAGE" "$SCRIPT_DIR/fixtures" >/dev/null || fail "fixture/client build failed"
for mode in native wrapper; do
    if [[ "$mode" == native ]]; then
        # Exercise production default CMD; test-only hook explicitly prepares Derby.
        CID=$(docker run -d -e TEST_NATIVE_CMD=true "$TEST_IMAGE")
    else
        CID=$(docker run -d "$TEST_IMAGE" start-metastore --db-type derby \
            --config /kubedoop/run/conf --hive-bin-dir /kubedoop/hive-metastore/bin)
    fi
    wait_for_server
    check_foreground_jvm
    db="lifecycle_$mode"
    client create "$db" >/dev/null || fail "Thrift database creation failed"
    stop_and_check 1 TERM
    docker start "$CID" >/dev/null
    wait_for_server
    check_foreground_jvm
    [[ "$(client check "$db" 2>/dev/null | tail -1)" == "$db" ]] || fail "restart lost database identity or contents"
    stop_and_check 2 INT
    logs=$(docker logs "$CID" 2>&1)
    if [[ "$mode" == native ]]; then
        [[ "$(grep -c '^TEST_HIVE_SCHEMA_INIT$' <<< "$logs")" == 1 ]] || fail "schema was recreated on restart"
    else
        [[ "$(grep -c '^No valid schema found, initializing schema' <<< "$logs")" == 1 ]] || fail "wrapper recreated a valid schema"
    fi
    docker rm "$CID" >/dev/null
    CID=""
    echo "ok - Hive $mode launcher serves real Thrift requests, preserves database contents and handles TERM/INT"
done
