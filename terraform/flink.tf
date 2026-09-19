locals {
  flink_deployment_file = yamldecode(file("${path.module}/../kubernetes/flink/flink-deployment.yaml"))
  flink_deployment_manifest = merge(local.flink_deployment_file, {
    spec = merge(local.flink_deployment_file.spec, { image = var.flink_job_image })
  })
}

# The FlinkDeployment CRD must already exist at plan time. Apply helm_release.flink_operator first.
resource "kubernetes_manifest" "flink_job" {
  manifest = local.flink_deployment_manifest

  depends_on = [
    helm_release.flink_operator,
    kubernetes_job_v1.minio_buckets,
    kubernetes_manifest.kafka_topics,
    kubernetes_secret_v1.flink_s3,
  ]
}
