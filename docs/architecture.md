# Architecture

## 1. Complete platform

```mermaid
flowchart LR
  P[Python producer] -->|machine.telemetry.raw| K[(Kafka on Strimzi)]
  K --> F[Apache Flink job]
  F -->|valid + enriched| E[(machine.telemetry.enriched)]
  F -->|invalid| D[(machine.telemetry.dlq)]
  E --> C[Python consumer]
  F -->|checkpoints / savepoints via S3 API| M[(MinIO + PVC)]
  K --> PM[Prometheus]
  F --> PM
  KU[Kubernetes / kubelet] --> PM
  PM --> G[Grafana]
```

All arrows stay inside the kind network except browser access through `kubectl port-forward`. Kubernetes Service DNS provides addresses such as `local-kafka-kafka-bootstrap.streaming.svc.cluster.local` and `minio.storage.svc.cluster.local`.

## 2. Kafka data flow

```mermaid
flowchart LR
  P[Producer replicas] --> B[Bootstrap Service]
  B --> R0[raw partition 0]
  B --> R1[raw partition 1]
  B --> R2[raw partition 2]
  R0 --> FG[Flink consumer group]
  R1 --> FG
  R2 --> FG
  FG --> V{Valid?}
  V -->|yes| EN[3-partition enriched topic]
  V -->|no| DLQ[1-partition DLQ]
  EN --> CG[learning consumer group]
```

A key is intentionally not set, so Kafka distributes records among partitions. Ordering is guaranteed only within one partition. Flink parallelism 2 can consume two partitions concurrently; one subtask can receive the remaining partition. Consumer-group offsets identify the next records each group should read.

## 3. Flink job

```mermaid
flowchart LR
  S[KafkaSource: raw JSON] --> V[ProcessFunction: validate]
  V -->|invalid side output| DS[KafkaSink: DLQ]
  V -->|valid| EN[enrich processedAt + status]
  EN --> WT[event timestamp + 5s watermark]
  WT --> ES[KafkaSink: enriched]
  V -. operator state .-> CP[checkpoint every 10s]
  CP --> S3[(MinIO S3 API)]
```

The current transform is stateless, but checkpoints still persist Kafka source offsets and sink progress. This makes failure/replay behavior observable now and leaves the correct foundation for later keyed state or windows.

The JobManager coordinates the job graph and checkpoints. TaskManagers execute parallel subtasks in slots. Two TaskManager slots and job parallelism 2 allow two copies of each parallel operator. Backpressure propagates upstream when a downstream operator cannot accept records fast enough.

## 4. Kubernetes namespaces

```mermaid
flowchart TB
  CL[kind cluster]
  CL --> ST[streaming]
  CL --> PR[processing]
  CL --> SO[storage]
  CL --> OB[observability]
  ST --> STR[Strimzi Operator]
  ST --> KF[Kafka + topics]
  ST --> AP[producer + consumer]
  PR --> FO[Flink Operator]
  PR --> FD[FlinkDeployment resources]
  SO --> MI[MinIO + PVC + bucket Job]
  OB --> KP[kube-prometheus-stack]
```

Namespaces isolate names and provide an RBAC boundary; they do not provide network isolation by themselves. The application ServiceAccount has no Kubernetes API token. Operator ServiceAccounts receive the API permissions their Helm charts require.

## 5. Terraform, Helm, and operators

```mermaid
flowchart TD
  TF[Terraform configuration] --> HP[Helm provider]
  TF --> KP[Kubernetes provider]
  HP --> H1[Strimzi Helm release]
  H1 --> CRD1[Kafka CRDs + controller]
  KP --> KCR[Kafka / KafkaNodePool / KafkaTopic CRs]
  CRD1 --> KCR
  KCR --> STR[Strimzi reconciliation]
  STR --> KRES[PodSet, Pods, Services, PVCs, Secrets]
  HP --> H2[Flink Operator Helm release]
  H2 --> CRD2[FlinkDeployment CRD + controller]
  KP --> FCR[FlinkDeployment CR]
  CRD2 --> FCR
  FCR --> FOR[Flink reconciliation]
  FOR --> FRES[JobManager / TaskManager resources]
```

Terraform does not create Kafka broker Pods directly. It creates the Kafka custom resource. Strimzi observes that resource and creates/repairs the implementation. The same relationship applies to `FlinkDeployment`.

This also explains the two-phase bootstrap: `kubernetes_manifest` asks the Kubernetes API for a custom resource's schema during `terraform plan`. Therefore the Helm releases must install CRDs first; an HCL `depends_on` controls apply order but cannot make a missing schema exist during planning.

## Storage and failure boundaries

- Kafka and MinIO use kind's dynamic `standard` StorageClass. A PVC binds to a host-path volume inside a kind node.
- Deleting a Pod retains its PVC. Deleting the kind cluster deletes the Docker nodes and their local volume data.
- Flink checkpoints/savepoints use the MinIO Service, not the TaskManager filesystem, so a TaskManager replacement can restore from shared object storage.
- `deleteClaim: true` makes Kafka storage disposable when the Kafka cluster is destroyed. This is appropriate only for the lab.

## Resource envelope

| Area | Approximate steady RAM |
|---|---:|
| kind/Kubernetes system | 0.5–1.0 GB |
| Strimzi + Kafka + exporter | 1.2–1.8 GB |
| Flink operator + job | 1.5–2.2 GB |
| MinIO | 0.3–0.5 GB |
| Prometheus + Grafana + operators | 1.0–1.6 GB |
| Apps and headroom | 0.3–0.8 GB |
| **Total** | **about 5–7 GB** |

If memory is tight, install through Flink first and add observability last. Do not shrink Kafka or Flink JVM memory below the configured values until the base path works.
