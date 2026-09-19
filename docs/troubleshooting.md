# Troubleshooting

Start with the earliest failing layer. A red application Pod is often caused by an earlier operator, image, PVC, DNS, or credential problem.

## Universal first checks

```bash
kubectl config current-context
docker info
kubectl get nodes
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp | tail -50
./scripts/health-check.sh
```

## Terraform cannot plan a custom resource

Symptom: `no matches for kind`, `failed to determine resource GVK`, or a missing REST mapping.

Cause: the CRD is not installed yet.

```bash
make terraform-operators
kubectl get crd kafkas.kafka.strimzi.io flinkdeployments.flink.apache.org
make terraform-plan
```

If a chart install failed, inspect Helm and operator Pods before retrying:

```bash
helm list -A
helm status strimzi-kafka-operator -n streaming
helm status flink-kubernetes-operator -n processing
```

## Pod is `ImagePullBackOff`

Local app images are not in a public registry. Build and load them into kind:

```bash
make images
kubectl rollout restart deployment/telemetry-producer deployment/telemetry-consumer -n streaming
kubectl annotate flinkdeployment telemetry-enricher -n processing learning/restarted="$(date +%s)" --overwrite
```

Confirm the exact image in the Pod matches the Makefile tag and `imagePullPolicy: IfNotPresent`.

## Kafka is not Ready

```bash
kubectl describe kafka local-kafka -n streaming
kubectl get kafkanodepool,strimzipodset,pod,pvc -n streaming
kubectl logs deployment/strimzi-cluster-operator -n streaming --tail=200
kubectl describe pod local-kafka-dual-role-0 -n streaming
```

Common causes are insufficient Docker memory, an unbound PVC, or an unsupported version combination. This repository pins Strimzi 1.2.0 with Kafka 4.3.1.

## Producer cannot connect

```bash
kubectl logs deployment/telemetry-producer -n streaming
kubectl get service local-kafka-kafka-bootstrap -n streaming
kubectl get endpointslice -n streaming -l kubernetes.io/service-name=local-kafka-kafka-bootstrap
kubectl run dns-test --rm -it --restart=Never --image=busybox:1.37 -- \
  nslookup local-kafka-kafka-bootstrap.streaming.svc.cluster.local
```

If DNS resolves but the endpoint is empty, Kafka is not Ready.

## FlinkDeployment is stuck or failing

```bash
kubectl describe flinkdeployment telemetry-enricher -n processing
kubectl logs deployment/flink-kubernetes-operator -n processing --tail=200
kubectl logs -n processing -l component=jobmanager --tail=200
kubectl get secret minio-credentials -n processing
kubectl get pods -n processing -o wide
```

Check for missing local image, S3 authentication, Kafka DNS, insufficient TaskManager memory, or a failed savepoint during an upgrade.

## Checkpoints fail

```bash
kubectl rollout status deployment/minio -n storage
kubectl get service,endpointslice,pvc -n storage
kubectl logs deployment/minio -n storage --tail=100
kubectl logs -n processing -l component=jobmanager --tail=200 | grep -i -E 'checkpoint|s3|minio'
```

Verify the three buckets exist and that the Secret in `processing` matches the MinIO Secret in `storage` without printing secret values.

## Prometheus target is down

```bash
kubectl get podmonitor -n observability -o yaml
kubectl get pods -n streaming --show-labels
kubectl get pods -n processing --show-labels
kubectl logs deployment/monitoring-kube-prometheus-operator -n observability --tail=200
```

Compare monitor selectors, namespace selectors, and port names with the target Pod spec. Use Prometheus **Status → Target health** for the scrape error.

## Laptop pressure

Symptoms include Pending Pods, OOMKilled containers, slow reconciliation, or Docker restarts.

```bash
kubectl get pods -A --field-selector=status.phase=Pending
kubectl describe nodes | grep -A8 'Allocated resources'
kubectl get events -A --sort-by=.lastTimestamp | grep -E 'OOM|FailedScheduling|Evicted'
```

Allocate 8 GB to Docker Desktop. If needed, destroy observability first and continue the Kafka/Flink lessons without it:

```bash
terraform -chdir=terraform destroy -target=helm_release.observability
```

Finish with a full plan so targeted operations do not become the normal desired state.
