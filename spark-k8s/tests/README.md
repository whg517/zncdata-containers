# Spark process lifecycle regressions

Run from the repository root against the current source-built image:

```bash
bash spark-k8s/tests/source-entrypoint-framework.sh
bash spark-k8s/tests/source-runner.sh
bash spark-k8s/tests/image-entrypoint-framework.sh IMAGE
bash spark-k8s/tests/image-native-launchers.sh IMAGE
bash spark-k8s/tests/image-spark-lifecycle.sh IMAGE
```

The framework source suite exercises hook discovery and lifecycle state transitions. Run
it as root too to cover rejected non-root-owned hooks. The image suite checks
the exact vendored scripts, UID, protected runtime paths, Tini orphan reaping,
stdin and structured stdout, exit statuses, bounded shutdown and hook ordering.

The runner source suite checks the adapter's role dispatch, exec PID, exit status,
argument boundaries and silent handling of sensitive options with a capture
fixture. The separate native launcher suite below checks actual Spark behavior.

The native launcher suite runs the actual Spark JVM command builder, instrumenting
only the final service JVM. It checks master, worker, history, driver and executor
class selection, argument boundaries, executor option ordering, managed JVM PID,
signal forwarding and status retention. It does not simulate a Kubernetes cluster.

The application suite runs real PySpark computation, writes and rereads Parquet
data across a same-container restart, and feeds real event logs into HistoryServer.
It checks HistoryServer HTTP results, restart, TERM/INT shutdown and exactly-once
hooks. All files, containers and derived images are private disposable fixtures;
no external cluster, database, host mount or published port is used.

Production role commands are `master`, `worker URL`, `history`, `driver ARGS` and
`executor ARGS`; arbitrary commands pass through unchanged. Driver requires
`SPARK_DRIVER_BIND_ADDRESS`; executor requires the usual Spark Kubernetes
environment including driver URL, executor identity, memory, cores and pod fields.
Native Spark scripts are unchanged. Explicit daemon scripts retain native daemon
behavior and should not be used as the supervised foreground command. The default
command displays `spark-submit --help`; no workload or external state is created.

Pre/post hooks follow the other universal images' root-owned executable contract
under `/kubedoop/mount/{pre-script,post-script}`. Diagnostics go to stderr and do
not print command arguments. Kubernetes end-to-end scheduling, standalone master
and worker networking, external storage authentication and operator migration
are outside these image-level regressions.
