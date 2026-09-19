resource "helm_release" "strimzi_operator" {
  name       = "strimzi-kafka-operator"
  namespace  = module.namespaces["streaming"].name
  repository = "https://strimzi.io/charts/"
  chart      = "strimzi-kafka-operator"
  version    = "1.2.0"

  atomic  = true
  wait    = true
  timeout = 600

  values = [yamlencode({
    watchNamespaces = [module.namespaces["streaming"].name]
    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { cpu = "500m", memory = "512Mi" }
    }
  })]
}
