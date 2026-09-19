locals {
  kafka_topic_manifests = {
    raw      = "topic-raw.yaml"
    enriched = "topic-enriched.yaml"
    dlq      = "topic-dlq.yaml"
  }
}

resource "kubernetes_config_map_v1" "kafka_metrics" {
  metadata {
    name      = "kafka-metrics"
    namespace = module.namespaces["streaming"].name
    labels    = merge(local.common_labels, { app = "strimzi" })
  }

  data = {
    "kafka-metrics-config.yml" = file("${path.module}/../kubernetes/kafka/kafka-metrics-config.yml")
  }
}

# The Strimzi CRD must already exist at plan time. Apply helm_release.strimzi_operator first.
resource "kubernetes_manifest" "kafka_node_pool" {
  manifest = yamldecode(file("${path.module}/../kubernetes/kafka/kafka-node-pool.yaml"))

  depends_on = [helm_release.strimzi_operator]
}

resource "kubernetes_manifest" "kafka" {
  manifest = yamldecode(file("${path.module}/../kubernetes/kafka/kafka.yaml"))

  depends_on = [
    kubernetes_config_map_v1.kafka_metrics,
    kubernetes_manifest.kafka_node_pool,
  ]
}

resource "kubernetes_manifest" "kafka_topics" {
  for_each = local.kafka_topic_manifests
  manifest = yamldecode(file("${path.module}/../kubernetes/kafka/${each.value}"))

  depends_on = [kubernetes_manifest.kafka]
}
