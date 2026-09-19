resource "kubernetes_secret_v1" "minio" {
  metadata {
    name      = "minio-credentials"
    namespace = module.namespaces["storage"].name
    labels    = local.common_labels
  }

  data = {
    root-user     = var.minio_root_user
    root-password = var.minio_root_password
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "flink_s3" {
  metadata {
    name      = "minio-credentials"
    namespace = module.namespaces["processing"].name
    labels    = local.common_labels
  }

  data = {
    access-key = var.minio_root_user
    secret-key = var.minio_root_password
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim_v1" "minio" {
  metadata {
    name      = "minio-data"
    namespace = module.namespaces["storage"].name
    labels    = local.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "standard"
    resources {
      requests = { storage = "5Gi" }
    }
  }
}

resource "kubernetes_deployment_v1" "minio" {
  metadata {
    name      = "minio"
    namespace = module.namespaces["storage"].name
    labels    = merge(local.common_labels, { app = "minio" })
  }

  spec {
    replicas = 1
    strategy { type = "Recreate" }

    selector { match_labels = { app = "minio" } }

    template {
      metadata { labels = { app = "minio" } }

      spec {
        security_context { fs_group = 1000 }

        container {
          name  = "minio"
          image = "quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z"
          args  = ["server", "/data", "--console-address", ":9001"]

          port {
            name           = "api"
            container_port = 9000
          }
          port {
            name           = "console"
            container_port = 9001
          }

          env {
            name = "MINIO_ROOT_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.minio.metadata[0].name
                key  = "root-user"
              }
            }
          }
          env {
            name = "MINIO_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.minio.metadata[0].name
                key  = "root-password"
              }
            }
          }

          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }

          readiness_probe {
            http_get {
              path = "/minio/health/ready"
              port = "api"
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
          liveness_probe {
            http_get {
              path = "/minio/health/live"
              port = "api"
            }
            initial_delay_seconds = 15
            period_seconds        = 15
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          security_context {
            run_as_user                = 1000
            run_as_group               = 1000
            run_as_non_root            = true
            allow_privilege_escalation = false
            capabilities { drop = ["ALL"] }
          }
        }

        volume {
          name = "data"
          persistent_volume_claim { claim_name = kubernetes_persistent_volume_claim_v1.minio.metadata[0].name }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "minio" {
  metadata {
    name      = "minio"
    namespace = module.namespaces["storage"].name
    labels    = local.common_labels
  }
  spec {
    selector = { app = "minio" }
    port {
      name        = "api"
      port        = 9000
      target_port = "api"
    }
  }
}

resource "kubernetes_service_v1" "minio_console" {
  metadata {
    name      = "minio-console"
    namespace = module.namespaces["storage"].name
    labels    = local.common_labels
  }
  spec {
    selector = { app = "minio" }
    port {
      name        = "console"
      port        = 9001
      target_port = "console"
    }
  }
}

resource "kubernetes_job_v1" "minio_buckets" {
  metadata {
    name      = "create-minio-buckets"
    namespace = module.namespaces["storage"].name
    labels    = local.common_labels
  }

  spec {
    backoff_limit = 10
    template {
      metadata { labels = { app = "create-minio-buckets" } }
      spec {
        restart_policy = "OnFailure"
        container {
          name    = "mc"
          image   = "quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z"
          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            until mc alias set local http://minio.storage.svc.cluster.local:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"; do sleep 2; done
            mc mb --ignore-existing local/flink-checkpoints local/flink-savepoints local/iceberg-data
          EOT
          ]
          env {
            name = "MINIO_ROOT_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.minio.metadata[0].name
                key  = "root-user"
              }
            }
          }
          env {
            name = "MINIO_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.minio.metadata[0].name
                key  = "root-password"
              }
            }
          }
          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { cpu = "100m", memory = "64Mi" }
          }
        }
      }
    }
  }

  wait_for_completion = true
  depends_on = [
    kubernetes_deployment_v1.minio,
    kubernetes_service_v1.minio,
  ]

  timeouts { create = "5m" }
}
