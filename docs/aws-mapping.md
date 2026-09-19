# Local-to-AWS mapping

The mapping is conceptual, not always one-to-one. The local lab teaches control planes, data planes, identity, storage, and observability boundaries that carry into AWS.

| Local component | Approximate AWS equivalent | What changes in production |
|---|---|---|
| Docker Desktop | Developer workstation / container runtime | Workloads run on managed or self-managed fleet capacity. |
| kind | Amazon EKS | AWS manages the Kubernetes control plane; nodes use EC2 managed node groups, Karpenter, or Fargate. |
| kind worker container | EC2 worker node | Use multiple Availability Zones, autoscaling, hardened AMIs, and IAM roles. |
| kind `standard` host-path storage | EBS CSI-backed PersistentVolumes | EBS volumes persist independently of Pods; topology and backups matter. |
| Strimzi Kafka | Amazon MSK, or Strimzi on EKS | MSK manages brokers; Strimzi retains Kubernetes-level control. Both need multi-AZ design, encryption, authentication, and capacity planning. |
| Kafka KRaft controller/broker | MSK broker/controller service internals | AWS manages more lifecycle details in MSK; APIs and client concepts remain Kafka. |
| KafkaTopic CR | MSK topic created through Kafka API/IaC automation | Topic configuration is often managed through Terraform providers, scripts, or a platform API. |
| Python producer/consumer | ECS/EKS/Lambda applications | Images live in ECR; use IAM/network controls, TLS/SASL, autoscaling, and deployment pipelines. |
| Flink Kubernetes Operator | Flink Operator on EKS | You own Flink runtime/operator upgrades, scaling, HA, and Kubernetes integration. |
| FlinkDeployment | Amazon Managed Service for Apache Flink application | Managed Flink reduces runtime operations but exposes a different deployment/IaC model. |
| MinIO | Amazon S3 | S3 is regional, massively durable managed object storage; use IAM instead of static access keys. |
| MinIO bucket Job | Terraform `aws_s3_bucket` resources | Configure encryption, versioning, lifecycle, ownership, access logging, and policies. |
| Kubernetes Secret | AWS Secrets Manager / SSM Parameter Store + External Secrets | Encrypt secrets, rotate them, audit access, and use IRSA/Pod Identity where possible. |
| ServiceAccount/RBAC | EKS ServiceAccount/RBAC + IAM role | Kubernetes authorization and AWS API authorization are separate layers joined by Pod Identity/IRSA. |
| ClusterIP Service/DNS | EKS VPC CNI + CoreDNS + Services | Add VPC/subnet/security-group design, ingress/load balancers, private endpoints, and NetworkPolicies. |
| Prometheus | Amazon Managed Service for Prometheus, or Prometheus on EKS | Add durable ingestion, retention, alert routing, cross-account access, and cost/cardinality controls. |
| Grafana | Amazon Managed Grafana, or Grafana on EKS | Add SSO, workspace/network controls, dashboard provisioning, and team permissions. |
| Local Terraform state | S3 backend with native lockfile | Encrypt state, restrict access, enable bucket versioning, lock concurrent applies, and separate environments/accounts. |

## Two reasonable AWS target architectures

### More managed

```text
EKS/ECS producers → Amazon MSK → Amazon Managed Service for Apache Flink
                                  ├→ MSK enriched/DLQ topics
                                  └→ Amazon S3 state/data
Amazon Managed Prometheus → Amazon Managed Grafana
```

This reduces operational ownership but requires learning each managed service's deployment, IAM, networking, limits, and pricing model.

### Kubernetes-centric

```text
Amazon EKS
├── Strimzi Kafka (or connect privately to MSK)
├── Flink Kubernetes Operator
├── application workloads
└── collectors/agents
Amazon S3 for Flink state
Amazon Managed Prometheus/Grafana or in-cluster monitoring
```

This most closely resembles the lab and gives maximum control, but the platform team owns more upgrades, failure modes, storage, scaling, and on-call responsibility.

## Production controls absent locally

- Multi-account environment isolation and IAM least privilege.
- Multi-AZ capacity, disruption budgets, topology spread, and disaster recovery.
- Private VPC endpoints, security groups, NetworkPolicies, TLS, and certificate rotation.
- ECR image scanning/signing and controlled promotion.
- Encrypted, remote Terraform state and CI approvals.
- SLOs, alerts, runbooks, audit logs, backup/restore tests, and cost controls.
- Schema governance. Apicurio locally maps conceptually to AWS Glue Schema Registry or a self-managed registry on EKS.
