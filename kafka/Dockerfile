# syntax=docker/dockerfile:1
# check=error=true


# stage: kafka-builder
FROM zncdatadev/image/java-devel AS kafka-builder

ARG PRODUCT_VERSION
ARG JMX_EXPORTER_VERSION
ARG SCALA_VERSION

WORKDIR /build

# setup jmx_exporter
COPY kubedoop/jmx/config-${JMX_EXPORTER_VERSION} /kubedoop/jmx

RUN <<EOF
    set -e
    # check JMX_EXPORTER_VERSION
    if [ -n "${JMX_EXPORTER_VERSION}" ]; then
        curl -sSfL \
            https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar \
            -o /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar

        ln -s /kubedoop/jmx/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar /kubedoop/jmx/jmx_prometheus_javaagent.jar
    else
        echo "JMX_EXPORTER_VERSION is not set"
    fi
EOF

COPY kubedoop/ /build/

# build kafka
# use cache locked to fix gradle concurrency lock issue https://github.com/gradle/gradle/issues/8750#issuecomment-2312378643
RUN --mount=type=cache,sharing=locked,target=/root/.gradle <<EOF
    set -ex
    mkdir -p /build/kafka-src
    pushd /build/kafka-src
    curl -sSfL \
        https://github.com/apache/kafka/archive/refs/tags/${PRODUCT_VERSION}.tar.gz \
        | tar xzf - --strip-components=1
    ./gradlew clean releaseTarGz -x test
    tar -xzf core/build/distributions/kafka_${SCALA_VERSION}-${PRODUCT_VERSION}.tgz -C /kubedoop
    ln -s /kubedoop/kafka_${SCALA_VERSION}-${PRODUCT_VERSION} /kubedoop/kafka
    popd

    # smoke test
    /kubedoop/kafka/bin/kafka-server-start.sh --version

    # cleanup source
    rm -rf /build/kafka-src
EOF

RUN <<EOF
    set -e
    ARCH=$(uname -m)
    ARCH="${ARCH/amd64/x86_64}"
    ARCH="${ARCH/aarch64/arm64}"
    curl -sSfL -o /usr/local/bin/log4shell \
        https://github.com/lunasec-io/lunasec/releases/download/v1.6.1-log4shell/log4shell_1.6.1-log4shell_Linux_${ARCH}
    chmod +x /usr/local/bin/log4shell
    /usr/local/bin/log4shell patch --backup --force-patch --json /kubedoop/kafka
EOF


## stage: final
FROM zncdatadev/image/java-base

ARG PRODUCT_VERSION

WORKDIR /kubedoop

COPY --from=kafka-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

ENV KAFKA_HOME=/kubedoop/kafka
ENV PATH="${KAFKA_HOME}/bin:${PATH}"

USER kubedoop

# smoke test
RUN kafka-server-start.sh --version

WORKDIR /kubedoop/kafka

CMD ["kafka-server-start.sh", "config/server.properties"]
