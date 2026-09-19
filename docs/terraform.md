# Terraform guide

Terraform owns the desired platform configuration after kind creates the cluster. The root module uses local state in `terraform/terraform.tfstate`; no cloud backend is needed.

## Concepts in this repository

| Concept | Where | Meaning |
|---|---|---|
| Provider | `providers.tf` | Configures how Terraform talks to Kubernetes and Helm through `kind-streaming-lab`. |
| Resource | `minio.tf`, `apps.tf`, others | Something Terraform creates and tracks, such as a Deployment, Secret, Helm release, or custom resource. |
| Variable | `variables.tf` | An input: cluster name, kubeconfig path, local image names, or development credentials. |
| Local | `locals.tf` | A reusable expression internal to this module, such as namespace names and Kafka DNS. |
| Output | `outputs.tf` | A useful value shown after apply, such as inspection commands or the Grafana ClusterIP. |
| Data source | `data.tf` | Reads the Grafana Service after Helm creates it; it does not create anything. |
| Dependency | `depends_on` and references | Orders resources: the bucket Job needs MinIO; the Flink CR needs buckets/topics/operator. |
| Module | `modules/namespace` | A small reusable unit instantiated four times with `for_each`. |
| State | `terraform.tfstate` | Terraform's mapping from resource addresses to real Kubernetes object identities and attributes. |

The namespace module exists because four resources have the same behavior and only their names differ. There are no generic `helm-release` or `manifest` modules: they would hide the chart-specific fields this lab is meant to teach.

## Normal command lifecycle

Run from the repository root:

```bash
terraform -chdir=terraform init
terraform fmt -check -recursive terraform
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=tfplan
terraform -chdir=terraform apply tfplan
terraform -chdir=terraform show
terraform -chdir=terraform state list
terraform -chdir=terraform destroy
```

- `init` downloads the exact provider versions selected by `versions.tf` and `.terraform.lock.hcl`.
- `fmt` makes HCL layout deterministic.
- `validate` checks syntax, references, and provider schemas; it does not prove a runtime workload is healthy.
- `plan` refreshes real objects, compares them to configuration/state, and proposes changes.
- `apply tfplan` executes exactly the saved plan.
- `destroy` follows the dependency graph in reverse and removes managed objects.

Never delete the kind cluster before `terraform destroy` if you want Terraform to remove resources cleanly. If you do, the state still records objects in a cluster that no longer exists. Because this is a disposable lab, you can then remove the orphaned local state deliberately, but do not copy that habit to production.

## Why operator installation is a separate apply

`Kafka`, `KafkaTopic`, and `FlinkDeployment` are not built-in Kubernetes kinds. Their CRDs provide API schemas. The Kubernetes provider must read those schemas during planning, before resource dependencies are applied.

First install CRDs:

```bash
make terraform-operators-plan
make terraform-operators
```

Then run a normal complete plan:

```bash
make terraform-plan
make terraform-apply
```

`depends_on` still matters after schema discovery: it prevents custom resources from being applied before their operator release is ready. It cannot solve a schema that is absent at plan time.

## State experiments

List and inspect addresses:

```bash
terraform -chdir=terraform state list
terraform -chdir=terraform state show 'module.namespaces["streaming"].kubernetes_namespace_v1.this'
terraform -chdir=terraform state show kubernetes_deployment_v1.producer
```

State can contain sensitive values even when CLI output redacts them. `.gitignore` excludes `*.tfstate*`; back it up only to encrypted storage.

To see drift safely:

```bash
kubectl scale deployment/telemetry-producer -n streaming --replicas=3
terraform -chdir=terraform plan
```

The plan should propose `replicas = 1`. Apply to restore the declared value:

```bash
terraform -chdir=terraform apply
```

## Dependencies to trace

```text
namespace module
├── operator Helm releases
├── MinIO / apps / observability
Strimzi release → KafkaNodePool → Kafka → KafkaTopics → producer/consumer
MinIO Deployment + Service → bucket Job
Flink release + topics + bucket Job + S3 Secret → FlinkDeployment
observability Helm release → dashboard ConfigMap → Grafana data source/output
```

Terraform waits for Kubernetes/Helm API completion where configured. Operators reconcile asynchronously afterward, so a successful `terraform apply` does not by itself mean Kafka or Flink is Ready. Use `kubectl wait`, status conditions, events, and `scripts/health-check.sh`.

## Secrets

Inputs come from environment variables:

```bash
set -a; source .env; set +a
terraform -chdir=terraform plan
```

Terraform creates namespaced Kubernetes Secrets, and Pods use `secretKeyRef`; credentials are not written into the Flink manifest. However, local state still contains them. Production alternatives include External Secrets Operator plus AWS Secrets Manager, SOPS-encrypted manifests, or another audited secret workflow.

## Targeted applies

`-target` is used here only to teach and bootstrap CRDs incrementally. It can omit unrelated changes, which is why Learning Mode ends with a full plan/apply. Routine production workflows should avoid targets except for exceptional recovery.
