variable "cluster_name" {
  description = "kind cluster name. kind writes the context as kind-<name>."
  type        = string
  default     = "streaming-lab"
}

variable "kubeconfig_path" {
  description = "Kubeconfig read by the Kubernetes and Helm providers."
  type        = string
  default     = "~/.kube/config"
}

variable "minio_root_user" {
  description = "Development-only MinIO root user. Supply through TF_VAR_minio_root_user."
  type        = string
  sensitive   = true
}

variable "minio_root_password" {
  description = "Development-only MinIO root password. Supply through TF_VAR_minio_root_password."
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Development-only Grafana admin password. Supply through TF_VAR_grafana_admin_password."
  type        = string
  sensitive   = true
}

variable "producer_image" {
  description = "Producer image loaded into the kind nodes."
  type        = string
  default     = "local/telemetry-producer:dev"
}

variable "consumer_image" {
  description = "Consumer image loaded into the kind nodes."
  type        = string
  default     = "local/telemetry-consumer:dev"
}

variable "flink_job_image" {
  description = "Flink job image loaded into the kind nodes."
  type        = string
  default     = "local/flink-telemetry-job:dev"
}
