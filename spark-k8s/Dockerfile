# syntax=docker/dockerfile:1

ARG JAVA_BASE_VERSION
ARG JAVA_DEVEL_VERSION

FROM docker.io/library/gradle:8 AS gradle-builder

ARG PRODUCT_VERSION
ARG JMX_EXPORTER_VERSION

WORKDIR /build

RUN <<EOT
    cat > build.gradle <<EOF
apply plugin: 'base'

repositories {
    mavenLocal()
    mavenCentral()
}

configurations {
    toCopy
}

dependencies {
    toCopy 'org.apache.spark:spark-hadoop-cloud_2.13:${PRODUCT_VERSION}'
    toCopy 'com.fasterxml.jackson.dataformat:jackson-dataformat-xml:2.14.2'
}

task download(type: Copy) {
    from configurations.toCopy
    into '/jars'
}

EOF

    # show dependencies graph
    gradle --no-daemon dependencies

    # download dependencies
    gradle download --no-daemon

EOT

## stage: java-builder
FROM quay.io/zncdatadev/java-devel:${JAVA_DEVEL_VERSION}-kubedoop0.0.0-dev AS java-builder

ARG PRODUCT_VERSION
ARG HADOOP_VERSION
ARG JMX_EXPORTER_VERSION

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

# build spark
RUN <<EOF
    set -e
    mkdir -p /build/spark-src
    pushd /build/spark-src
    curl -sSfL \
        https://archive.apache.org/dist/spark/spark-${PRODUCT_VERSION}/spark-${PRODUCT_VERSION}.tgz \
        | tar xzf - --strip-components=1
    ./dev/make-distribution.sh \
        -Dhadoop.version=${HADOOP_VERSION} \
        -Dmaven.javadoc.skip=true \
        -DskipTests \
        -Phadoop-3 \
        -Pkubernetes \
        -Phive \
        -Phive-thriftserver
    
    cp -r dist /kubedoop/spark-${PRODUCT_VERSION}
    
    ln -s /kubedoop/spark-${PRODUCT_VERSION} /kubedoop/spark
    ln -s /kubedoop/spark/jars/spark-examples_*.jar /kubedoop/spark/examples.jar
    popd
EOF

COPY --from=gradle-builder /jars/ /kubedoop/spark/jars/

# smoke test
RUN /kubedoop/spark/bin/spark-shell --version

## stage: final
FROM quay.io/zncdatadev/java-base:${JAVA_BASE_VERSION}-kubedoop0.0.0-dev

ARG PRODUCT_VERSION
ARG PYTHON_VERSION

RUN <<EOF
    set -e
    microdnf update
    microdnf install \
        procps \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-pip \
        java-${JAVA_VERSION}-openjdk-devel \
        zip

    microdnf clean all
    ln -s /usr/bin/python${PYTHON_VERSION} /usr/bin/python
    ln -s /usr/bin/pip-${PYTHON_VERSION} /usr/bin/pip
EOF

COPY --from=java-builder --chown=kubedoop:kubedoop /kubedoop/ /kubedoop/

ENV SPARK_HOME=/kubedoop/spark

RUN <<EOT
    set -e
    cat >> /etc/profile.d/spark.sh <<'EOF'
export PATH=${SPARK_HOME}/bin:${PATH}
export PYSPARK_PYTHON=/usr/bin/python
export PYTHONPATH=${SPARK_HOME}/python:${PYTHONPATH}
EOF

EOT

WORKDIR /kubedoop/spark

USER kubedoop

# smoke test
RUN source /etc/profile.d/spark.sh && spark-shell --version
