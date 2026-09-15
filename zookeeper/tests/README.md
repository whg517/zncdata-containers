# ZooKeeper Entrypoint Tests

This directory contains lightweight tests for the zookeeper entrypoint framework.

## Source behavior test

Run this before or after an image build when changing `zookeeper/kubedoop/lib/*.sh`:

```bash
zookeeper/tests/source-entrypoint-framework.sh
```

This sources the framework libraries directly from the working tree. It validates
library behavior only; it does not prove the final image wiring.

## Image behavior test

Run this after `make zookeeper-build`:

```bash
zookeeper/tests/image-entrypoint-framework.sh
```

Or pass an explicit image:

```bash
zookeeper/tests/image-entrypoint-framework.sh quay.io/zncdatadev/zookeeper:3.9.3-kubedoop0.0.0-dev
```

This runs containers from the built image and validates the final image wiring:
entrypoint files, runtime user, exit-code propagation, root-owned runtime hooks,
and signal forwarding through tini and `/kubedoop/bin/entrypoint.sh`.

Regression coverage includes ConfigMap-style `..data` symlinks, checking the
target's ownership and execute permission, stdin-consuming hooks followed by
another hook, status 127 on normal and signal-driven exits, and omission of
command arguments from logs in both normal and debug mode. Hooks receive
`/dev/null` as stdin; they must use explicit files or environment variables for
input.
