FROM flink:1.20.1-scala_2.12-java17

USER root
RUN mkdir -p /opt/flink/usrlib /opt/flink/plugins/s3-fs-hadoop \
    && cp /opt/flink/opt/flink-s3-fs-hadoop-*.jar /opt/flink/plugins/s3-fs-hadoop/ \
    && cp /opt/flink/opt/flink-metrics-prometheus-*.jar /opt/flink/lib/
COPY --chown=flink:flink target/flink-telemetry-job.jar /opt/flink/usrlib/flink-telemetry-job.jar
USER flink
