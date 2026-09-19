# A data source reads an object created by another resource rather than creating it.
data "kubernetes_service_v1" "grafana" {
  metadata {
    name      = "monitoring-grafana"
    namespace = module.namespaces["observability"].name
  }

  depends_on = [helm_release.observability]
}
