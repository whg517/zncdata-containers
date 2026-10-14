ARG IMAGE
FROM ${IMAGE}
USER root
COPY 10-prepare.sh /kubedoop/mount/pre-script/10-prepare.sh
COPY 10-check-stopped.sh /kubedoop/mount/post-script/10-check-stopped.sh
RUN chmod 0755 /kubedoop/mount/pre-script/10-prepare.sh /kubedoop/mount/post-script/10-check-stopped.sh
ENV JAVA_OPTS="-Xms128m -Xmx512m -XX:ActiveProcessorCount=2" \
    SPRING_CONFIG_ADDITIONAL_LOCATION=file:/kubedoop/run/lifecycle.properties
USER kubedoop
