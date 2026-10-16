#!/bin/bash
# Real krb5kdc/kadmind, ticket issuance, admin RPC, persistence and both init modes.
set -euo pipefail
directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
image="${1:-quay.io/zncdatadev/krb5:1.21.1-kubedoop0.0.0-dev}"
fixture="krb5-kdc-test:$(date +%s)-$$"
containers=()
cleanup() {
    for cid in "${containers[@]}"; do docker rm -fv "$cid" >/dev/null 2>&1 || true; done
    docker image rm "$fixture" >/dev/null 2>&1 || true
}
trap cleanup EXIT
fail() {
    echo "not ok - $*" >&2
    for cid in "${containers[@]}"; do
        docker inspect -f 'state={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} error={{.State.Error}}' "$cid" >&2 || true
        docker logs "$cid" >&2 2>&1 || true
        # Process names/states only: never dump setup arguments containing passwords.
        docker exec "$cid" ps -eo pid,ppid,pgid,stat,comm >&2 2>&1 || true
    done
    exit 1
}
docker build --pull=false --build-arg BASE_IMAGE="$image" -t "$fixture" "$directory/fixtures"
ready() {
    local cid=$1
    for ((i=0;i<90;i++)); do
        if printf '%s\n' test-admin-password | docker exec -i "$cid" kinit admin/admin@LIFECYCLE.TEST >/dev/null 2>&1; then
            docker exec "$cid" klist -s && return 0
        fi
        [[ "$(docker inspect -f '{{.State.Running}}' "$cid")" == true ]] || break
        sleep 1
    done
    docker logs "$cid" 2>&1 | tail -n 25 >&2
    return 1
}
for mode in foreground systemd; do
    options=()
    command=()
    if [[ $mode == foreground ]]; then command=(--foreground); else options=(--privileged --cgroupns=private); fi
    cid=$(docker run -d --hostname kdc.lifecycle.test "${options[@]}" "$fixture" "${command[@]}" \
        --password test-master-password --kadmin-password test-admin-password --realm LIFECYCLE.TEST --domain lifecycle.test)
    containers+=("$cid")
    ready "$cid" || fail "$mode KDC readiness"
    comm=$(docker exec "$cid" cat /proc/1/comm)
    if [[ $mode == systemd ]]; then
        [[ $comm == systemd ]] || fail 'default systemd PID1 changed'
        docker exec "$cid" systemctl is-active krb5kdc kadmin kubedoop-lifecycle.service
    else
        [[ $comm == tini ]] || fail 'foreground Tini missing'
    fi
    docker exec "$cid" bash -c 'test "$(stat -c %a /tmp/krb5kdc_admin_password)" = 600'
    startup_logs=$(docker logs "$cid" 2>&1)
    [[ $startup_logs != *test-master-password* && $startup_logs != *test-admin-password* ]] || fail "$mode password logging"
    # Authenticated administrative RPC, not just local database access.
    docker exec "$cid" kadmin -p admin/admin@LIFECYCLE.TEST -w test-admin-password \
        -q 'addprinc -pw persistent-user-password persistent@LIFECYCLE.TEST'
    docker exec "$cid" kadmin.local -q 'getprinc persistent@LIFECYCLE.TEST' | grep -q 'Principal: persistent@LIFECYCLE.TEST'
    for cycle in 1 2 3; do
        printf '%s\n' persistent-user-password | docker exec -i "$cid" kinit persistent@LIFECYCLE.TEST >/dev/null
        docker exec "$cid" klist -s
        stop_started=$SECONDS
        if [[ $cycle == 1 && $mode == foreground ]]; then
            docker kill --signal TERM "$cid" >/dev/null
        elif [[ $cycle == 2 && $mode == foreground ]]; then
            docker kill --signal INT "$cid" >/dev/null
        else
            docker stop -t 45 "$cid" >/dev/null
        fi
        status=$(docker wait "$cid")
        [[ $status != 137 ]] || fail "$mode forced KILL"
        events=$(docker cp "$cid:/kubedoop/run/events" - | tar -xO | tr '\n' ',')
        expected=""
        for ((j=0;j<cycle;j++)); do expected+=PRE,POST,; done
        [[ $events == "$expected" ]] || fail "$mode cycle=$cycle status=$status stop_seconds=$((SECONDS - stop_started)) hook order/count $events"
        if [[ $cycle -lt 3 ]]; then
            docker start "$cid" >/dev/null
            ready "$cid" || fail "$mode restart"
        fi
    done
    if [[ $mode == foreground ]]; then
        docker start "$cid" >/dev/null
        ready "$cid" || fail 'foreground failure-case restart'
        docker exec "$cid" pkill -TERM -x krb5kdc
        [[ "$(docker wait "$cid")" == 1 ]] || fail 'unexpected clean daemon exit must fail container'
        events=$(docker cp "$cid:/kubedoop/run/events" - | tar -xO | tr '\n' ',')
        [[ $events == PRE,POST,PRE,POST,PRE,POST,PRE,POST, ]] || fail 'daemon failure did not drain peer before post'
    fi
    echo "ok - $mode real KDC tickets/admin RPC, same-CID principal persistence, three orderly stops and hooks"
done
