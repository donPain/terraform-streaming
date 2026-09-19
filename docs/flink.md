# Flink guide

## Runtime concepts

- **Operator:** A transformation in the job graph, such as source, validation, watermark assignment, or sink. This is different from the Kubernetes Operator.
- **Source/sink:** Source reads raw Kafka records; two sinks write enriched and DLQ records.
- **JobManager:** Coordinates scheduling, checkpoints, recovery, and the REST API.
- **TaskManager:** Worker process that executes parallel operator subtasks.
- **Slot:** TaskManager capacity unit. This lab provides two slots.
- **Parallelism:** Number of concurrent subtasks. The job uses two; Kafka raw has three partitions.
- **State:** Data retained by an operator. The current transform is stateless, while Kafka source progress and sink coordination are checkpointed.
- **Checkpoint:** Automatic consistent snapshot for failure recovery while a job runs.
- **Savepoint:** User/operator-triggered snapshot intended for controlled upgrades, rescaling, or migration.
- **Backpressure:** A slow downstream task makes upstream tasks slow their output rather than grow memory without bound.

## Operator reconciliation

The `FlinkDeployment` is desired state. The Flink Kubernetes Operator creates JobManager and TaskManager resources, submits the JAR, observes REST status, and reconciles changes. Inspect both layers:

```bash
kubectl get flinkdeployment telemetry-enricher -n processing -o yaml
kubectl get deployment,pod,service,configmap -n processing
kubectl logs deployment/flink-kubernetes-operator -n processing --tail=100
kubectl logs -n processing -l component=jobmanager --tail=100
kubectl logs -n processing -l component=taskmanager --tail=100
```

Open the Flink UI:

```bash
kubectl port-forward -n processing service/telemetry-enricher-rest 8081:8081
open http://localhost:8081
```

The UI shows the job graph, subtasks, checkpoints, records, exceptions, and backpressure.

## Checkpoints in MinIO

Flink loads the S3 filesystem plugin from the custom image and uses:

```text
s3.endpoint: http://minio.storage.svc.cluster.local:9000
s3.path.style.access: true
state.checkpoints.dir: s3://flink-checkpoints/telemetry-enricher
state.savepoints.dir: s3://flink-savepoints/telemetry-enricher
```

Credentials arrive through `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from a namespaced Kubernetes Secret. They are not embedded in the Flink CR.

List checkpoint objects without installing `mc` locally:

```bash
kubectl run minio-inspect -n storage --rm -it --restart=Never \
  --image=quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z \
  --env="MC_HOST_local=http://${TF_VAR_minio_root_user}:${TF_VAR_minio_root_password}@minio.storage.svc.cluster.local:9000" \
  -- ls --recursive local/flink-checkpoints
```

The credentials appear in your shell history with that educational command. Prefer the MinIO console or a temporary Pod using `secretKeyRef` if history exposure matters.

## Trigger a savepoint

Ask the operator to trigger one by adding a nonce:

```bash
kubectl patch flinkdeployment telemetry-enricher -n processing --type=merge \
  -p '{"spec":{"job":{"savepointTriggerNonce":1}}}'
kubectl get flinkdeployment telemetry-enricher -n processing \
  -o jsonpath='{.status.jobStatus.savepointInfo.lastSavepoint.location}{"\n"}'
```

This is a live/manual change, so Terraform may later report drift. For a repeat trigger, use a new integer. The `upgradeMode: savepoint` setting asks the operator to take a savepoint for spec upgrades.

## Recovery exercises

Delete a TaskManager and watch replacement/recovery:

```bash
kubectl delete pod -n processing -l component=taskmanager
kubectl get pods -n processing -w
```

Stop MinIO and inspect checkpoint failures:

```bash
kubectl scale deployment/minio -n storage --replicas=0
kubectl logs -n processing -l component=jobmanager -f | grep -i checkpoint
kubectl scale deployment/minio -n storage --replicas=1
```

The job can process temporarily while checkpointing fails, but it loses its recent recovery point. Prolonged failure should alert in production.
