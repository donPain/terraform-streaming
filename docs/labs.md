# LEARNING LABS

Run these only after `make health` reports OK. Keep three terminals open: the exercise, `kubectl get pods -A -w`, and logs/metrics. Every lab includes a deliberate failure and a recovery.

## Lab 1: Kill a Kafka Pod

```bash
kubectl delete pod local-kafka-dual-role-0 -n streaming --wait=false
kubectl get pod,strimzipodset,pvc -n streaming -w
```

**Observe:** the Pod disappears, Kafka is briefly unavailable because this lab has one broker, and the Strimzi-managed PodSet creates a replacement with the same stable name/PVC. Producer logs show retries; after readiness, delivery resumes. Inspect events and Strimzi logs:

```bash
kubectl get events -n streaming --sort-by=.lastTimestamp
kubectl logs deployment/strimzi-cluster-operator -n streaming --tail=100
```

**Recover:** reconciliation is automatic. Wait for `kubectl wait kafka/local-kafka -n streaming --for=condition=Ready --timeout=10m`. Production replication would keep other brokers serving during one restart.

## Lab 2: Kill a Flink TaskManager

```bash
kubectl delete pod -n processing -l component=taskmanager --wait=false
kubectl get pods -n processing -w
```

**Observe:** a replacement TaskManager appears, the job may enter restarting, then returns to RUNNING. The Flink UI shows restart/checkpoint history. Kafka records may be replayed after the last completed checkpoint because sinks use at-least-once delivery.

```bash
kubectl get flinkdeployment telemetry-enricher -n processing \
  -o jsonpath='{.status.jobStatus.state}{"\n"}'
kubectl logs -n processing -l component=jobmanager --tail=200 | grep -i -E 'restart|checkpoint|recover'
```

**Recover:** the Flink operator handles it. If it does not, inspect the FlinkDeployment status and JobManager exception before changing anything.

## Lab 3: Scale producer replicas

```bash
kubectl scale deployment/telemetry-producer -n streaming --replicas=5
kubectl get pods -n streaming -l app=telemetry-producer
```

**Observe:** five independent producers raise the Kafka message-rate panel. Raw records spread across three partitions. Flink parallelism remains two, so increased source backlog/lag may appear.

```bash
kubectl exec -n streaming local-kafka-dual-role-0 -c kafka -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group flink-telemetry-enricher
```

**Recover:** `terraform -chdir=terraform apply -target=kubernetes_deployment_v1.producer` restores one replica. A normal full plan will also show and repair this drift.

## Lab 4: Increase Kafka topic partitions

Kafka can increase but cannot decrease partition count.

```bash
kubectl patch kafkatopic machine.telemetry.raw -n streaming --type=merge \
  -p '{"spec":{"partitions":6}}'
kubectl wait kafkatopic/machine.telemetry.raw -n streaming --for=condition=Ready --timeout=5m
kubectl exec -n streaming local-kafka-dual-role-0 -c kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --describe --topic machine.telemetry.raw
```

**Observe:** partitions 3–5 are added. Existing records do not move, and key-to-partition mapping can change when partition count changes.

**Recover:** because Kafka cannot shrink to three, update `kubernetes/kafka/topic-raw.yaml` to six and apply Terraform so code/state accept reality. To return to three, destroy/recreate this disposable topic and lose its data.

## Lab 5: Change Flink parallelism

```bash
kubectl patch flinkdeployment telemetry-enricher -n processing --type=merge \
  -p '{"spec":{"job":{"parallelism":1}}}'
kubectl get flinkdeployment,pods -n processing -w
```

**Observe:** with `upgradeMode: savepoint`, the operator takes a savepoint, redeploys, and restores at parallelism one. The TaskManager still has two slots; one is unused. Source partition assignments consolidate.

**Recover:** patch back to two or run a Terraform apply. Inspect the last savepoint location before/after:

```bash
kubectl get flinkdeployment telemetry-enricher -n processing \
  -o jsonpath='{.status.jobStatus.savepointInfo.lastSavepoint.location}{"\n"}'
```

## Lab 6: Generate malformed events and observe the DLQ

```bash
kubectl set env deployment/telemetry-producer -n streaming MALFORMED_PERCENT=0.5
make consume-dlq
```

**Observe:** about half the generated events omit `machineId`. Flink emits a JSON wrapper with `failedAt`, `error`, and original `raw` content to `machine.telemetry.dlq`; valid records continue to enriched.

**Recover:** `terraform -chdir=terraform apply -target=kubernetes_deployment_v1.producer` restores 2%. In production, alert on DLQ rate and build a controlled replay/remediation path.

## Lab 7: Stop MinIO and observe checkpoint failures

```bash
kubectl scale deployment/minio -n storage --replicas=0
kubectl logs -n processing -l component=jobmanager -f | grep -i checkpoint
```

**Observe:** the Flink job can keep processing, but checkpoints time out/fail because the S3 endpoint has no backing Pod. The last successful recovery point gets older.

**Recover:**

```bash
kubectl scale deployment/minio -n storage --replicas=1
kubectl rollout status deployment/minio -n storage
```

Wait for new completed checkpoints in the Flink UI/Prometheus. Terraform can also restore replicas. Production S3 is a managed regional service rather than one Pod.

## Lab 8: Create Flink backpressure

The job includes an off-by-default learning throttle. Set the validation operator to sleep 200 ms/record and increase producers:

```bash
kubectl patch flinkdeployment telemetry-enricher -n processing --type=json \
  -p='[{"op":"replace","path":"/spec/podTemplate/spec/containers/0/env/4/value","value":"200"}]'
kubectl scale deployment/telemetry-producer -n streaming --replicas=10
```

**Observe:** input capacity exceeds the roughly five records/second per validation subtask. In the Flink UI, inspect the job graph's Backpressure tab. Grafana should show backpressured time and Kafka consumer lag growing.

**Recover:**

```bash
kubectl patch flinkdeployment telemetry-enricher -n processing --type=json \
  -p='[{"op":"replace","path":"/spec/podTemplate/spec/containers/0/env/4/value","value":"0"}]'
kubectl scale deployment/telemetry-producer -n streaming --replicas=1
terraform -chdir=terraform apply
```

Watch lag drain. Production tuning starts by locating the slow operator, then considers I/O, serialization, state, partitioning, resources, and parallelism.

## Lab 9: Delete the producer Deployment and restore with Terraform

```bash
kubectl delete deployment telemetry-producer -n streaming
kubectl get pods -n streaming -l app=telemetry-producer
terraform -chdir=terraform plan
terraform -chdir=terraform apply
```

**Observe:** unlike deleting a Pod, deleting the Deployment removes its controller, so Kubernetes does not recreate the Pod. Terraform detects the managed resource is absent and recreates it.

**Recover:** the apply is the recovery. This demonstrates the boundary: Kubernetes reconciles Pods from Deployments; Terraform reconciles Deployments from HCL.

## Lab 10: Create Terraform configuration drift

Change a managed field without deleting the object:

```bash
kubectl set resources deployment/telemetry-consumer -n streaming \
  --limits=cpu=400m,memory=192Mi
terraform -chdir=terraform plan
```

**Observe:** refresh reads the live Deployment and the plan proposes configured limits (`200m`, `128Mi`). Review the exact `~ update in-place` diff.

**Recover:**

```bash
terraform -chdir=terraform apply
terraform -chdir=terraform plan
```

The second plan should show no changes. In production, avoid routine `kubectl edit`; make reviewed code the source of truth and alert on unauthorized drift.
