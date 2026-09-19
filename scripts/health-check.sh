#!/usr/bin/env bash
set -uo pipefail

failures=0

report() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf '%-12s OK\n' "$name:"
  else
    printf '%-12s NOT READY\n' "$name:"
    failures=$((failures + 1))
  fi
}

kubernetes_ready() {
  kubectl get nodes --no-headers | awk 'NF && $2 !~ /^Ready/ {exit 1} END {if (NR == 0) exit 1}'
}

kafka_ready() {
  kubectl wait -n streaming kafka/local-kafka --for=condition=Ready --timeout=1s
  kubectl wait -n streaming kafkatopic --all --for=condition=Ready --timeout=1s
}

flink_ready() {
  test "$(kubectl get flinkdeployment telemetry-enricher -n processing -o jsonpath='{.status.jobStatus.state}')" = "RUNNING"
}

producer_ready() {
  kubectl rollout status -n streaming deployment/telemetry-producer --timeout=1s
}

consumer_ready() {
  kubectl rollout status -n streaming deployment/telemetry-consumer --timeout=1s
}

minio_ready() {
  kubectl rollout status -n storage deployment/minio --timeout=1s
  test "$(kubectl get job create-minio-buckets -n storage -o jsonpath='{.status.succeeded}')" = "1"
}

prometheus_ready() {
  kubectl wait -n observability pod -l app.kubernetes.io/name=prometheus --for=condition=Ready --timeout=1s
}

grafana_ready() {
  kubectl rollout status -n observability deployment/monitoring-grafana --timeout=1s
}

report Kubernetes kubernetes_ready
report Kafka kafka_ready
report Flink flink_ready
report Producer producer_ready
report Consumer consumer_ready
report MinIO minio_ready
report Prometheus prometheus_ready
report Grafana grafana_ready

exit "$failures"
