# Kafka lifecycle verification

The Kafka image vendors its lifecycle entrypoint framework locally:
tini as PID 1, root-owned pre/post hooks, SIGTERM/SIGINT forwarding, bounded
shutdown, exit-status propagation, and preserved main-process stdin.

Kafka remains responsible for its broker configuration and storage. The image
does not auto-format KRaft data or generate cluster IDs in production. Operators
must supply their existing configuration and format new KRaft storage explicitly.
The default `kafka-server-start.sh config/server.properties` command is unchanged;
Kafka 3.x's bundled default requires ZooKeeper, while Kafka 4.0's KRaft default
requires formatted storage.

In Kubernetes, pass the broker command through container `args` to retain the
image's tini/entrypoint chain. An explicit container `command` replaces that
chain. Existing operator-managed shell launchers therefore need to adopt this
contract before they can use image-level hooks and signal management; this
image change does not alter operator container specifications.

Run source regressions without building an image:

```bash
kafka/tests/source-entrypoint-framework.sh
```

Build one version and check the actual image:

```bash
.scripts/build.sh kafka:4.0.0 --platform linux/amd64
IMAGE=quay.io/zncdatadev/kafka:4.0.0-kubedoop0.0.0-dev
kafka/tests/image-entrypoint-framework.sh "$IMAGE"
kafka/tests/image-kafka-lifecycle.sh "$IMAGE"
```

The framework suite covers ConfigMap-style symlinks, ownership/executable checks,
ordered hooks, stdin-reading hooks, main stdin, application exit codes, repeated
signals during shutdown/post-hooks, SIGKILL escalation, and omission of command
arguments from logs. Hooks use `/dev/null` for stdin; use explicit files or env
variables for their input.

The broker test builds a disposable derived image with test-only hooks and an
explicit single-node KRaft configuration, compatible with all four supported
versions. It formats only an empty test data directory, creates a topic,
produces and consumes two messages, and checks graceful shutdown. It restarts
the same container and verifies the same KRaft identity and messages, then checks
that post-hooks run once per shutdown after the broker JVM exits. No host ports,
existing volumes, or running Kafka clusters are used.

CI runs both image suites for every supported version on amd64 and arm64.
