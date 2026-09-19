output "namespaces" {
  description = "Namespaces managed by the reusable namespace module."
  value       = { for name, namespace in module.namespaces : name => namespace.name }
}

output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap address reachable from inside the cluster."
  value       = local.kafka_bootstrap_servers
}

output "learning_commands" {
  description = "Useful local inspection commands."
  value = {
    nodes      = "kubectl get nodes -o wide"
    kafka      = "kubectl get kafka,kafkanodepool,kafkatopic -n streaming"
    flink      = "kubectl get flinkdeployment -n processing"
    grafana    = "kubectl port-forward -n observability svc/monitoring-grafana 3000:80"
    minio      = "kubectl port-forward -n storage svc/minio-console 9001:9001"
    prometheus = "kubectl port-forward -n observability svc/monitoring-kube-prometheus-prometheus 9090:9090"
  }
}

output "grafana_cluster_ip" {
  description = "Cluster-internal Grafana Service IP read through a Terraform data source."
  value       = data.kubernetes_service_v1.grafana.spec[0].cluster_ip
}
