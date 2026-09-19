resource "helm_release" "flink_operator" {
  name       = "flink-kubernetes-operator"
  namespace  = module.namespaces["processing"].name
  repository = "https://archive.apache.org/dist/flink/flink-kubernetes-operator-1.16.0/"
  chart      = "flink-kubernetes-operator"
  version    = "1.16.0"

  atomic  = true
  wait    = true
  timeout = 600

  values = [yamlencode({
    watchNamespaces = [module.namespaces["processing"].name]
    webhook         = { create = false }
    metrics         = { port = 9999 }
    operatorPod = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
  })]
}
