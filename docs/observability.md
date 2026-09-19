# Observability guide

The `kube-prometheus-stack` Helm release installs Prometheus Operator, Prometheus, Grafana, kube-state-metrics, and built-in Kubernetes dashboards. Alertmanager and node-exporter are disabled to keep the laptop footprint conservative.

## Discovery path

```text
Kafka/Flink Pod labels + named metrics ports
  → PodMonitor resources
  → Prometheus Operator
  → Prometheus scrape configuration
  → Prometheus time series
  → Grafana panels
```

The PodMonitors are rendered by the Helm release from Terraform values. Prometheus is configured to discover monitors in every namespace.

```bash
kubectl get podmonitor -A
kubectl describe podmonitor monitoring-kafka-resources -n observability
kubectl describe podmonitor monitoring-flink-jobs -n observability
kubectl get prometheus -n observability
```

Names include the Helm release prefix and can vary slightly by chart version; `kubectl get podmonitor -n observability` is authoritative.

## Prometheus

```bash
make prometheus
```

Open <http://localhost:9090>, then inspect **Status → Target health**. Expected targets include Kafka/Flink plus Kubernetes components. Try these queries:

```promql
up
sum(rate(kafka_server_brokertopicmetrics_messagesinpersec_total[1m])) by (topic)
kafka_server_replicamanager_leadercount
sum(rate(flink_taskmanager_job_task_operator_numRecordsIn[1m]))
sum(rate(flink_taskmanager_job_task_operator_numRecordsOut[1m]))
flink_jobmanager_job_numberOfCompletedCheckpoints
max(flink_taskmanager_job_task_backPressuredTimeMsPerSecond)
sum(rate(container_cpu_usage_seconds_total{namespace="processing",container!=""}[1m])) by (pod)
sum(container_memory_working_set_bytes{namespace="processing",container!=""}) by (pod)
```

Metric names are generated from runtime versions and can change. If a panel is blank, search the Prometheus expression browser for `{__name__=~".*kafka.*"}` or `{__name__=~".*flink.*"}`, then update the dashboard query with the metric actually exposed.

## Grafana

```bash
make grafana
```

Open <http://localhost:3000>. User is `admin`; the password is `TF_VAR_grafana_admin_password` from `.env`. The **Local Streaming Platform** dashboard is loaded from `kubernetes/observability/local-streaming-dashboard.json` through a labeled ConfigMap.

The chart also supplies Kubernetes dashboards. Look for namespace/workload views to inspect Pod CPU and memory.

For richer Kafka views, import the JSON dashboards shipped by the exact Strimzi release from its official repository:

1. Visit the `examples/metrics/grafana-dashboards` directory for Strimzi 1.2.0.
2. In Grafana, choose **Dashboards → New → Import**.
3. Upload the broker or Kafka Exporter dashboard JSON.
4. Choose the existing Prometheus data source.

Keeping those large upstream JSON files out of this repository makes upgrades clearer: use dashboards matched to the installed Strimzi metric rules.

## Troubleshooting scrape targets

```bash
# Confirm labels and named ports match the PodMonitors.
kubectl get pods -n streaming --show-labels
kubectl get pods -n processing --show-labels
kubectl get pod -n processing -l component=taskmanager -o yaml | grep -A4 ports:

# Confirm endpoints answer from within the cluster.
kubectl port-forward -n processing pod/$(kubectl get pod -n processing -l component=taskmanager -o jsonpath='{.items[0].metadata.name}') 9249:9249
curl http://localhost:9249/metrics

# Inspect Prometheus Operator reconciliation.
kubectl logs -n observability deployment/monitoring-kube-prometheus-operator --tail=100
```

## Production differences

Persist or remotely write Prometheus data, deploy Alertmanager, protect UIs with TLS/SSO, define recording/alert rules, measure cardinality, size retention deliberately, and separate platform monitoring from application SLOs. AWS equivalents are covered in [aws-mapping.md](aws-mapping.md).
