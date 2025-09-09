locals {
  aks-cluster = {
    default_node_pool_node_count = 1
    default_node_pool_vm_size = "standard_d4ads_v6"
    agent_node_pool_node_count = 1
    agent_node_pool_vm_size = "standard_d4ads_v6"
    # container_registry_id = "/subscriptions/f411b60c-50d5-4fed-aea5-3d3f33f00a3f/resourceGroups/corp_name-iac-prod/providers/Microsoft.ContainerRegistry/registries/corp_namedockerprod"
  }
}

## 在每个region创建aks集群
resource "azurerm_kubernetes_cluster" "aks" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "aks-${each.value.short_name}"
  location                      = each.value.name
  resource_group_name           = azurerm_resource_group.rg[each.value.name].name

  dns_prefix                    = "aks-${each.value.short_name}"

  oidc_issuer_enabled           = true
  workload_identity_enabled     = true

  default_node_pool {
    name           = "system${each.value.short_name}"
    node_count     = local.aks-cluster.default_node_pool_node_count
    vm_size        = local.aks-cluster.default_node_pool_vm_size

    #zones = ["1", "2", "3"]  # available zone for node pool vm

    vnet_subnet_id = azurerm_subnet.aks_subnet[each.value.name].id
#     pod_subnet_id  = azurerm_subnet.pod_subnet[each.value.name].id

    temporary_name_for_rotation = "defaulttmp"

    upgrade_settings {
        max_surge                     = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # this is required for aks to enable managed prometheus and
  monitor_metrics {
    annotations_allowed = null
    labels_allowed      = null
  }

  network_profile {
    network_plugin = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    service_cidr   = "172.16.32.0/19"
    dns_service_ip = "172.16.32.10"
  }

  # enable KEDA
  workload_autoscaler_profile {
    keda_enabled  = true
  }

  # enable web app routing addon
  web_app_routing {
    dns_zone_ids = []
    
    # we disable default public nginx controller and create an internal one mannual using yaml later on 
    default_nginx_controller = "None"   
  }

  # enable all storage driver for aks cluster
  storage_profile {
    blob_driver_enabled = true
    disk_driver_enabled = true
    file_driver_enabled = true
    snapshot_controller_enabled = true
  }
  
  # ignore defender configuration changes
  lifecycle {
    ignore_changes = [ microsoft_defender ]
  }
}

# Update the AKS cluster to enable NAP using the azapi provider
resource "azapi_update_resource" "nap" {
  for_each = { for r in var.region_settings : r.name => r }

  type                    = "Microsoft.ContainerService/managedClusters@2024-09-02-preview"
  resource_id             = azurerm_kubernetes_cluster.aks[each.value.name].id
  ignore_missing_property = true
  body = {
    properties = {
      nodeProvisioningProfile = {
        mode = "Auto"
      }
    }
  }
}

//permission for aks assigned identity to aks vnet
resource "azurerm_role_assignment" "aks_vnet_contributor" {
  depends_on = [ azurerm_kubernetes_cluster.aks ]

  for_each = { for r in var.region_settings : r.name => r }

  principal_id = azurerm_kubernetes_cluster.aks[each.value.name].identity[0].principal_id
  role_definition_name             = "Network Contributor"
  scope                            = azurerm_virtual_network.vnet[each.value.name].id
  skip_service_principal_aad_check = true
}


//permission for aks assigned identity to resource group, for kapenter to link disk for cloning
//VM Restore Operator role could be also needed
resource "azurerm_role_assignment" "aks_rg_disk_snapshot_contributor" {
  depends_on = [ azurerm_kubernetes_cluster.aks ]
  for_each = { for r in var.region_settings : r.name => r }

  principal_id = azurerm_kubernetes_cluster.aks[each.value.name].identity[0].principal_id
  role_definition_name             = "Disk Snapshot Contributor"

  scope                            = azurerm_resource_group.rg[each.value.name].id
  skip_service_principal_aad_check = true
}

#output kubeconfig and write to local file
resource "local_file" "kubeconfig" {
  for_each     = { for r in var.region_settings : r.name => r }

  depends_on   = [ azurerm_kubernetes_cluster.aks ]
  filename     = "./kubeconfig-${each.value.name}"
  file_permission = "0600"
  content      = azurerm_kubernetes_cluster.aks[each.value.name].kube_config_raw
}

# create addtional node pool for aks cluster
# resource "azurerm_kubernetes_cluster_node_pool" "agentnode" {
#     for_each              = { for r in var.region_settings : r.name => r }
#     name                  = "agent${each.value.short_name}"
#     kubernetes_cluster_id = azurerm_kubernetes_cluster.aks[each.value.name].id
#     vm_size               = local.aks-cluster.agent_node_pool_vm_size
#     node_count            = local.aks-cluster.agent_node_pool_node_count
#     vnet_subnet_id        = azurerm_subnet.aks_subnet[each.value.name].id
# #     pod_subnet_id         = azurerm_subnet.pod_subnet[each.value.name].id
#     max_pods              = 50
#
#     #zones = ["1", "2", "3"]  # available zone for node pool vm
#
#     temporary_name_for_rotation = "agentnodetmp"
#
#     upgrade_settings {
#         max_surge                     = "10%"
#     }
#
# }


# add rbac for aks mi to access container registry
resource "azurerm_role_assignment" "aks_mi_container_registry_access" {
  for_each = { for r in var.region_settings : r.name => r }
  principal_id = azurerm_kubernetes_cluster.aks[each.value.name].kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope = var.azure_container_registry_id
}
