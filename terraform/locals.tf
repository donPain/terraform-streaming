locals {
  namespaces = toset([
    "streaming",
    "processing",
    "storage",
    "observability",
  ])

  common_labels = {
    "app.kubernetes.io/part-of"    = "local-streaming-platform"
    "app.kubernetes.io/managed-by" = "terraform"
  }

  kafka_bootstrap_servers = "local-kafka-kafka-bootstrap.streaming.svc.cluster.local:9092"
}
