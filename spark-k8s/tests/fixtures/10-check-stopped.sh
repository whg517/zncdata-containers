#!/bin/bash
set -euo pipefail
for cmdline in /proc/[0-9]*/cmdline; do
    [[ -r "$cmdline" ]] || continue
    if grep -aq 'org.apache.spark.deploy.history.HistoryServer' "$cmdline"; then
        echo 'Spark history JVM still running' >&2; exit 1
    fi
done
echo TEST_SPARK_POST_DONE
