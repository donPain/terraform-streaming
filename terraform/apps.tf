resource "kubernetes_service_account_v1" "telemetry_apps" {
  metadata {
    name      = "telemetry-apps"
    namespace = module.namespaces["streaming"].name
    labels    = local.common_labels
  }

  automount_service_account_token = false
}

resource "kubernetes_deployment_v1" "producer" {
  metadata {
    name      = "telemetry-producer"
    namespace = module.namespaces["streaming"].name
    labels    = merge(local.common_labels, { app = "telemetry-producer" })
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "telemetry-producer" }
    }

    template {
      metadata {
        labels = { app = "telemetry-producer" }
      }

      spec {
        service_account_name             = kubernetes_service_account_v1.telemetry_apps.metadata[0].name
        automount_service_account_token  = false
        termination_grace_period_seconds = 20

        security_context {
          run_as_non_root = true
          seccomp_profile { type = "RuntimeDefault" }
        }

        container {
          name              = "producer"
          image             = var.producer_image
          image_pull_policy = "IfNotPresent"

          env {
            name  = "KAFKA_BOOTSTRAP_SERVERS"
            value = local.kafka_bootstrap_servers
          }
          env {
            name  = "KAFKA_TOPIC"
            value = "machine.telemetry.raw"
          }
          env {
            name  = "EVENTS_PER_SECOND"
            value = "2"
          }
          env {
            name  = "MALFORMED_PERCENT"
            value = "0.02"
          }

          resources {
            requests = { cpu = "25m", memory = "64Mi" }
            limits   = { cpu = "200m", memory = "128Mi" }
          }

          readiness_probe {
            exec { command = ["/bin/sh", "-c", "kill -0 1"] }
            initial_delay_seconds = 3
            period_seconds        = 10
          }

          liveness_probe {
            exec { command = ["/bin/sh", "-c", "kill -0 1"] }
            initial_delay_seconds = 10
            period_seconds        = 20
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.kafka_topics]
}

resource "kubernetes_deployment_v1" "consumer" {
  metadata {
    name      = "telemetry-consumer"
    namespace = module.namespaces["streaming"].name
    labels    = merge(local.common_labels, { app = "telemetry-consumer" })
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "telemetry-consumer" }
    }

    template {
      metadata {
        labels = { app = "telemetry-consumer" }
      }

      spec {
        service_account_name             = kubernetes_service_account_v1.telemetry_apps.metadata[0].name
        automount_service_account_token  = false
        termination_grace_period_seconds = 20

        security_context {
          run_as_non_root = true
          seccomp_profile { type = "RuntimeDefault" }
        }

        container {
          name              = "consumer"
          image             = var.consumer_image
          image_pull_policy = "IfNotPresent"

          env {
            name  = "KAFKA_BOOTSTRAP_SERVERS"
            value = local.kafka_bootstrap_servers
          }
          env {
            name  = "KAFKA_TOPIC"
            value = "machine.telemetry.enriched"
          }
          env {
            name  = "KAFKA_GROUP_ID"
            value = "telemetry-learning-consumer"
          }

          resources {
            requests = { cpu = "25m", memory = "64Mi" }
            limits   = { cpu = "200m", memory = "128Mi" }
          }

          readiness_probe {
            exec { command = ["/bin/sh", "-c", "kill -0 1"] }
            initial_delay_seconds = 3
            period_seconds        = 10
          }

          liveness_probe {
            exec { command = ["/bin/sh", "-c", "kill -0 1"] }
            initial_delay_seconds = 10
            period_seconds        = 20
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.kafka_topics]
}
