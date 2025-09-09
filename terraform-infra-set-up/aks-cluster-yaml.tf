# wait 120s for nap to be applied and make sure its running
resource "time_sleep" "wait_2_minutes" {
  depends_on = [azapi_update_resource.nap]
  create_duration = "120s"

  # make sure sleep wait happens everytime when aks cluster is changed
  triggers = {
    aks_status = jsonencode(azurerm_kubernetes_cluster.aks)
  }
}

# apply yaml to all aks clusters make sure this will re-apply every time when yaml changes
# device plugin for nvidia gpu support
resource "null_resource" "apply_yaml_device_plugin" {
  for_each = { for r in var.region_settings : r.name => r }
  depends_on = [time_sleep.wait_2_minutes, local_file.kubeconfig]

  triggers = {
    yaml_hash  = filesha1("../aks-karpenter/ds-gpu-device-plugin.yaml")
    kubeconfig = local_file.kubeconfig[each.key].filename
    yaml_path  = "../aks-karpenter/ds-gpu-device-plugin.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl apply -f ${self.triggers.yaml_path}"
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
}

# # apply yaml to all aks clusters make sure this will re-apply every time when yaml changes
# # create karpenter node pool for t4 spot node
# resource "null_resource" "apply_yaml_nodeclass" {
#   for_each = { for r in var.region_settings : r.name => r }

#   depends_on = [time_sleep.wait_2_minutes, local_file.kubeconfig]

#   triggers = {
#     yaml_hash  = filesha1("../aks-config/nodeclass-t4-spot.yaml")
#     kubeconfig = local_file.kubeconfig[each.key].filename
#     yaml_path  = "../aks-config/nodeclass-t4-spot.yaml"
#   }

#   provisioner "local-exec" {
#     command = "kubectl apply -f ${self.triggers.yaml_path}"
#     environment = {
#       KUBECONFIG = self.triggers.kubeconfig
#     }
#   }
# }
