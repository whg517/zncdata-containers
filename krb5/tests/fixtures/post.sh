#!/bin/bash
set -euo pipefail
# In both modes post must follow termination of the real KDC and admin daemon.
if pgrep -x krb5kdc >/dev/null || pgrep -x kadmind >/dev/null; then
    ps -eo pid,ppid,pgid,stat,comm >&2
    exit 1
fi
printf 'POST\n' >> /kubedoop/run/events
[[ "${TEST_FAIL_POST:-false}" != true ]] || exit 23
