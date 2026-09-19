resource "helm_release" "observability" {
  name       = "monitoring"
  namespace  = module.namespaces["observability"].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "91.4.1"

  atomic  = true
  wait    = true
  timeout = 900

  values = [yamlencode({
    alertmanager          = { enabled = false }
    nodeExporter          = { enabled = false }
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }
    grafana = {
      persistence = { enabled = false }
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { cpu = "300m", memory = "256Mi" }
      }
      sidecar = { dashboards = { searchNamespace = "ALL" } }
    }
    prometheusOperator = {
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { cpu = "300m", memory = "256Mi" }
      }
    }
    prometheus = {
      prometheusSpec = {
        retention                               = "6h"
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        serviceMonitorNamespaceSelector         = {}
        podMonitorNamespaceSelector             = {}
        resources = {
          requests = { cpu = "150m", memory = "384Mi" }
          limits   = { cpu = "750m", memory = "768Mi" }
        }
      }
      additionalPodMonitors = [
        {
          name = "kafka-resources"
          selector = {
            matchExpressions = [{
              key      = "strimzi.io/kind"
              operator = "In"
              values   = ["Kafka"]
            }]
          }
          namespaceSelector   = { matchNames = [module.namespaces["streaming"].name] }
          podMetricsEndpoints = [{ port = "tcp-prometheus", path = "/metrics", interval = "15s" }]
        },
        {
          name                = "flink-jobs"
          selector            = { matchLabels = { monitoring = "flink" } }
          namespaceSelector   = { matchNames = [module.namespaces["processing"].name] }
          podMetricsEndpoints = [{ port = "metrics", path = "/metrics", interval = "15s" }]
        }
      ]
    }
  })]

  set_sensitive = [{
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }]
}

resource "kubernetes_config_map_v1" "grafana_dashboard" {
  metadata {
    name      = "local-streaming-dashboard"
    namespace = module.namespaces["observability"].name
    labels = merge(local.common_labels, {
      grafana_dashboard = "1"
    })
  }

  data = {
    "local-streaming.json" = file("${path.module}/../kubernetes/observability/local-streaming-dashboard.json")
  }

  depends_on = [helm_release.observability]
}
