module "namespaces" {
  for_each = local.namespaces
  source   = "./modules/namespace"

  name = each.value
  labels = merge(local.common_labels, {
    "platform.learning/purpose" = each.value
  })
}
