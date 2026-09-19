# Local Streaming Platform Learning Lab

A local, disposable platform for learning how Terraform, Kubernetes operators, Kafka, Flink, S3-compatible storage, Prometheus, and Grafana fit together. It uses Docker Desktop only: no cloud account, paid service, or AWS credential is required.

```text
telemetry-producer → Kafka raw → Flink validate/enrich ┬→ Kafka enriched → telemetry-consumer
                                                      ├→ Kafka DLQ
                                                      └→ MinIO checkpoints/savepoints
Kafka + Flink + Kubernetes → Prometheus → Grafana
```

The platform deliberately uses one Kafka broker/controller and one MinIO replica. That is enough to learn reconciliation and recovery, but it is not high availability. See [the architecture](docs/architecture.md) and [the AWS mapping](docs/aws-mapping.md).

## Prerequisites

Recommended Docker Desktop allocation: **4 CPUs, 8 GB RAM, and 20 GB free disk**. The steady-state stack normally uses about 5–7 GB of RAM. Shut down other local clusters first.

Install the tools on macOS:

```bash
brew install --cask docker
brew install terraform kubectl kind helm k9s maven openjdk@17
```

Start Docker Desktop, then verify it is running:

```bash
make check-tools
docker info
```

Java and Maven are needed only to compile the Flink learning job. `kubectl`, kind, Terraform, Helm, and k9s are the tools you will practice.

Create local development credentials without committing them:

```bash
cp .env.example .env
# Edit .env and change both passwords.
set -a
source .env
set +a
```

`.env`, Terraform state, and build outputs are ignored by Git. The provider still stores Secret values in local Terraform state, so protect that file. Production would use an encrypted remote backend plus an external secret manager.

## Quick start

Quick start is concise; Learning Mode below explains each boundary.

```bash
make cluster-create
make terraform-init
make terraform-validate
make images

# CRDs must exist before Terraform can plan their custom resources.
make terraform-operators-plan
make terraform-operators

make terraform-plan
make terraform-apply
make health
```

Watch data move through the system in separate terminals:

```bash
make producer-logs
make consumer-logs
make consume-dlq
```

Open the UIs:

```bash
make grafana     # http://localhost:3000, user admin, password from .env
make minio       # http://localhost:9001, credentials from .env
make prometheus  # http://localhost:9090
```

Destroy in the correct order so Terraform can remove custom resources before their CRDs:

```bash
make terraform-destroy
make cluster-delete
```

## Learning Mode

Run one section at a time. The targeted applies are teaching steps; the final full plan reconciles the complete desired state.

### 1. Create the Kubernetes cluster

```bash
kind create cluster --config kind/cluster.yaml
```

| Prompt | Explanation |
|---|---|
| **WHAT** | One control-plane and two worker nodes, each implemented as a Docker container. |
| **WHY** | Multiple nodes make scheduling, node identity, and failure boundaries visible. |
| **HOW** | kind starts containers, installs Kubernetes in them, and writes context `kind-streaming-lab` to kubeconfig. |
| **INSPECT** | `docker ps` and `kubectl cluster-info --context kind-streaming-lab`. |
| **BREAK** | `docker stop streaming-lab-worker`. |
| **RECOVER** | `docker start streaming-lab-worker`; watch `kubectl get nodes -w`. |
| **PRODUCTION** | EKS nodes are EC2 instances or Fargate capacity across Availability Zones, not local containers. |

### 2. Inspect Kubernetes before adding workloads

```bash
kubectl get nodes -o wide
kubectl get namespaces
kubectl get storageclass
kubectl get pods -A
```

| Prompt | Explanation |
|---|---|
| **WHAT** | The API server, system Pods, Nodes, namespaces, and kind's default `standard` StorageClass. |
| **WHY** | This baseline separates Kubernetes itself from resources the platform adds later. |
| **HOW** | `kubectl` sends authenticated requests using the current kubeconfig context. |
| **INSPECT** | `kubectl config current-context` and `kubectl describe node streaming-lab-worker`. |
| **BREAK** | Switch to a nonexistent context: `kubectl config use-context does-not-exist` fails safely. |
| **RECOVER** | `kubectl config use-context kind-streaming-lab`. |
| **PRODUCTION** | Access would use IAM-backed authentication, audited RBAC, and separate clusters/accounts. |

### 3. Initialize Terraform and create namespaces

```bash
terraform -chdir=terraform init
terraform fmt -check -recursive terraform
terraform -chdir=terraform validate
terraform -chdir=terraform plan -target=module.namespaces
terraform -chdir=terraform apply -target=module.namespaces
```

| Prompt | Explanation |
|---|---|
| **WHAT** | Provider plugins, local state, and four namespaces from one reusable module. |
| **WHY** | Namespaces partition names and RBAC scope; state maps HCL addresses to real objects. |
| **HOW** | The Kubernetes provider reads kubeconfig; `for_each` instantiates the namespace module four times. |
| **INSPECT** | `terraform -chdir=terraform state list` and `kubectl get ns --show-labels`. |
| **BREAK** | Delete one: `kubectl delete ns storage`. |
| **RECOVER** | Re-run the same targeted plan/apply; Terraform recreates the drifted namespace. |
| **PRODUCTION** | Use a remote, encrypted, locked backend and CI-reviewed plans. |

### 4. Install the Strimzi Operator

```bash
make strimzi-plan
make strimzi-install
kubectl get deployment,pods -n streaming
kubectl get crd | grep strimzi
```

| Prompt | Explanation |
|---|---|
| **WHAT** | A Helm release containing the Strimzi controller, ServiceAccount, RBAC, and Kafka CRDs. |
| **WHY** | Strimzi turns declarative `Kafka`, `KafkaNodePool`, and `KafkaTopic` objects into lower-level resources. |
| **HOW** | Helm installs manifests; the operator watches `streaming` and reconciles desired versus actual state. |
| **INSPECT** | `helm list -n streaming`, `kubectl api-resources | grep kafka.strimzi.io`, and operator logs. |
| **BREAK** | `kubectl scale deploy/strimzi-cluster-operator -n streaming --replicas=0`. |
| **RECOVER** | `terraform apply -chdir=terraform -target=helm_release.strimzi_operator`. |
| **PRODUCTION** | Pin tested versions, use dedicated operator lifecycle controls, and alert on reconciliation failures. |

### 5. Create Kafka

```bash
terraform -chdir=terraform plan -target=kubernetes_manifest.kafka
terraform -chdir=terraform apply -target=kubernetes_manifest.kafka
kubectl wait kafka/local-kafka -n streaming --for=condition=Ready --timeout=10m
```

| Prompt | Explanation |
|---|---|
| **WHAT** | One dual-role KRaft broker/controller, a 5 Gi PVC, Services, and Entity Operator Pods. |
| **WHY** | The broker stores event logs; the controller owns cluster metadata and leadership. |
| **HOW** | Terraform creates Strimzi custom resources; Strimzi creates Pods, Services, ConfigMaps, Secrets, and PVCs. |
| **INSPECT** | `make kafka-status`, `kubectl get strimzipodsets -n streaming`, and `kubectl describe kafka local-kafka -n streaming`. |
| **BREAK** | Delete `local-kafka-dual-role-0`. |
| **RECOVER** | Strimzi's generated PodSet recreates it and reattaches the PVC; watch `kubectl get pods -n streaming -w`. |
| **PRODUCTION** | Use at least three controllers and multiple brokers across zones with replication factor 3. |

### 6. Create topics

```bash
terraform -chdir=terraform plan -target=kubernetes_manifest.kafka_topics
terraform -chdir=terraform apply -target=kubernetes_manifest.kafka_topics
kubectl get kafkatopics -n streaming
```

| Prompt | Explanation |
|---|---|
| **WHAT** | Raw and enriched topics with three partitions, plus a one-partition DLQ. |
| **WHY** | Partitions are the unit of Kafka ordering and consumer parallelism; retention bounds local disk use. |
| **HOW** | Strimzi's Topic Operator converts each `KafkaTopic` CR into Kafka metadata. |
| **INSPECT** | `kubectl get kafkatopic machine.telemetry.raw -n streaming -o yaml` and commands in [Kafka notes](docs/kafka.md). |
| **BREAK** | Patch partitions to 4 manually and compare with Terraform configuration. |
| **RECOVER** | Update HCL/YAML to accept 4, or apply Terraform to restore supported fields. Kafka cannot decrease partitions. |
| **PRODUCTION** | Partition count follows throughput/key distribution; retention and replication follow durability requirements. |

### 7. Build, load, and deploy producer and consumer

```bash
make apps-test
make images
terraform -chdir=terraform apply \
  -target=kubernetes_deployment_v1.producer \
  -target=kubernetes_deployment_v1.consumer
kubectl get deploy,pods -n streaming
```

| Prompt | Explanation |
|---|---|
| **WHAT** | Non-root Deployments with probes, resource bounds, labels/selectors, and an API-less ServiceAccount. |
| **WHY** | The producer creates telemetry; the consumer exposes the enriched result and commits group offsets. |
| **HOW** | Local images are copied into kind nodes; clients resolve Kafka through cluster DNS. |
| **INSPECT** | `make producer-logs`, `make consumer-logs`, and `kubectl describe pod -n streaming <pod>`. |
| **BREAK** | `kubectl scale deploy/telemetry-producer -n streaming --replicas=0`. |
| **RECOVER** | Apply Terraform or scale back to one. |
| **PRODUCTION** | Push signed images to ECR, use TLS/SASL, NetworkPolicies, autoscaling, and workload identity. |

### 8. Install MinIO and create buckets

```bash
terraform -chdir=terraform plan -target=kubernetes_job_v1.minio_buckets
terraform -chdir=terraform apply -target=kubernetes_job_v1.minio_buckets
kubectl get deploy,svc,pvc,job -n storage
```

| Prompt | Explanation |
|---|---|
| **WHAT** | MinIO, a 5 Gi PVC, API/console Services, Secrets, and an idempotent bucket-creation Job. |
| **WHY** | Durable checkpoints/savepoints must outlive a Flink TaskManager Pod. |
| **HOW** | MinIO implements the S3 API locally; the Job creates three buckets with `mc mb --ignore-existing`. |
| **INSPECT** | `make minio`, `kubectl logs job/create-minio-buckets -n storage`, and `kubectl get pvc -n storage`. |
| **BREAK** | `kubectl scale deploy/minio -n storage --replicas=0`. |
| **RECOVER** | Scale to one or apply Terraform; the PVC retains objects. |
| **PRODUCTION** | Use S3 with IAM roles, encryption, lifecycle policies, versioning, and cross-region durability. |

### 9. Install the Flink Kubernetes Operator

```bash
make flink-operator-plan
make flink-operator-install
kubectl get deployment,pods -n processing
kubectl get crd flinkdeployments.flink.apache.org
```

| Prompt | Explanation |
|---|---|
| **WHAT** | The Flink controller, job ServiceAccount/RBAC, and FlinkDeployment CRD. |
| **WHY** | The operator owns job lifecycle, upgrades, restarts, and reconciliation. |
| **HOW** | It watches `processing` and turns `FlinkDeployment` into JobManager/TaskManager resources. |
| **INSPECT** | `helm list -n processing`, `kubectl auth can-i --as system:serviceaccount:processing:flink create pods -n processing`. |
| **BREAK** | Delete the operator Pod. |
| **RECOVER** | Its Deployment recreates it; existing Flink Pods continue while reconciliation pauses. |
| **PRODUCTION** | Enable webhook/cert-manager, operator HA, stricter RBAC, and an upgrade policy. |

### 10. Deploy the Flink job and verify state

```bash
terraform -chdir=terraform plan -target=kubernetes_manifest.flink_job
terraform -chdir=terraform apply -target=kubernetes_manifest.flink_job
kubectl get flinkdeployment,pods -n processing -w
make consume-enriched
make consume-dlq
```

| Prompt | Explanation |
|---|---|
| **WHAT** | A JobManager, TaskManager, two slots, Kafka source/sinks, validation side output, event-time watermarks, and 10-second checkpoints. |
| **WHY** | Flink processes unbounded streams and restores operator state after failures. |
| **HOW** | Raw JSON becomes enriched JSON; invalid records go to the side-output DLQ; checkpoint files use MinIO's S3 endpoint. |
| **INSPECT** | `make flink-status`, `make flink-logs`, Flink REST UI port-forward in [Flink notes](docs/flink.md), and MinIO bucket contents. |
| **BREAK** | Delete the TaskManager Pod or stop MinIO. |
| **RECOVER** | The operator recreates TaskManager; restart MinIO so checkpoints resume. |
| **PRODUCTION** | Use HA metadata storage, durable S3, tested savepoint upgrades, TLS, and exactly-once sinks where required. |

### 11. Install Prometheus and Grafana

```bash
terraform -chdir=terraform plan -target=helm_release.observability
terraform -chdir=terraform apply \
  -target=helm_release.observability \
  -target=kubernetes_config_map_v1.grafana_dashboard
kubectl get pods -n observability
```

| Prompt | Explanation |
|---|---|
| **WHAT** | Prometheus Operator, Prometheus, kube-state-metrics, Grafana, PodMonitors, and a dashboard ConfigMap. |
| **WHY** | Metrics make throughput, health, checkpoints, resources, and backpressure observable. |
| **HOW** | PodMonitors discover named Kafka/Flink metrics ports; Grafana's sidecar loads the dashboard ConfigMap. |
| **INSPECT** | `make prometheus`, check **Status → Targets**, then `make grafana`. |
| **BREAK** | Delete the Grafana Pod or remove the dashboard ConfigMap. |
| **RECOVER** | The Deployment recreates the Pod; Terraform restores the ConfigMap. |
| **PRODUCTION** | Use long-term metrics storage, authenticated ingress, alerts, recording rules, and managed AMP/Grafana if desired. |

### 12. Reconcile and validate the complete platform

```bash
terraform -chdir=terraform plan -out=tfplan
terraform -chdir=terraform apply tfplan
./scripts/health-check.sh
kubectl get pods -A
```

| Prompt | Explanation |
|---|---|
| **WHAT** | A full, non-targeted Terraform graph and a component health summary. |
| **WHY** | Targeted applies are for bootstrapping/learning; normal operations should reconcile the whole configuration. |
| **HOW** | Terraform refreshes state, detects drift, orders dependencies, and applies only the delta. |
| **INSPECT** | A second `terraform plan` should report no changes; run the validation checklist below. |
| **BREAK** | Change producer replicas manually: `kubectl scale deploy/telemetry-producer -n streaming --replicas=3`. |
| **RECOVER** | `terraform plan` shows drift; `terraform apply` returns it to one. |
| **PRODUCTION** | CI generates a reviewed plan from immutable code and applies with short-lived credentials. |

## Validation checklist

```bash
terraform fmt -check -recursive terraform
terraform -chdir=terraform validate
kubectl get nodes
kubectl wait kafka/local-kafka -n streaming --for=condition=Ready --timeout=10m
kubectl wait kafkatopic -n streaming --all --for=condition=Ready --timeout=5m
kubectl rollout status deployment/telemetry-producer -n streaming
kubectl get flinkdeployment telemetry-enricher -n processing
make consume-enriched
make consume-dlq
kubectl logs job/create-minio-buckets -n storage
kubectl get pods -n observability
make health
```

For checkpoint verification, open MinIO and confirm objects appear under `flink-checkpoints/telemetry-enricher`, or use the command in [docs/flink.md](docs/flink.md). A 2% malformed-event rate is enabled by default so the DLQ is visibly active.

## Repository guide

```text
kind/                         kind cluster topology
terraform/                    providers, resources, data, variables, outputs, state boundary
terraform/modules/namespace/  one intentionally small reusable module
kubernetes/kafka/             Strimzi custom resources and JMX metric rules
kubernetes/flink/             FlinkDeployment custom resource
kubernetes/observability/     version-controlled Grafana dashboard
apps/                         producer, consumer, and Flink job source/images
docs/                         concept guides, diagrams, labs, AWS mapping
scripts/health-check.sh        read-only component summary
```

Start with [architecture](docs/architecture.md), then use the [Kubernetes/k9s cheat sheet](docs/kubernetes.md) and complete all [Learning Labs](docs/labs.md).

## Deliberate first-version limits

- Schema Registry is omitted: plain JSON keeps the first data path inspectable. Add Apicurio Registry when schema evolution becomes the lesson.
- Kafka and MinIO are single replica: local recovery is demonstrated, not availability during failure.
- Flink sinks use at-least-once delivery: add transactional exactly-once only after learning checkpoint/replay behavior.
- Alertmanager and node-exporter are disabled to save memory; kubelet metrics still provide Pod CPU/memory.
