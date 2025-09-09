# 在每个region创建blob storage
resource "azurerm_storage_account" "storage_account" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "${var.storage_account_name_prefix}${each.value.short_name}"  #存储账号名称不支持连接符-,特殊符号等
  location                      = each.value.name
  resource_group_name           = azurerm_resource_group.rg[each.value.name].name
  account_tier                  = "Standard"
  account_replication_type      = "LRS"

  is_hns_enabled                = true    
  public_network_access_enabled = true
}

## allow aks mi to access storage queue and blob
resource "azurerm_role_assignment" "aks_mi_storage_account_access" {
  for_each = { for r in var.region_settings : r.name => r }
  principal_id = azurerm_kubernetes_cluster.aks[each.value.name].kubelet_identity[0].object_id
  role_definition_name = "Storage Queue Data Contributor"
  scope = azurerm_storage_account.storage_account[each.value.name].id
}

## allow aks workload identity access storage queue and blob, application pod will use workload identity as well
resource "azurerm_role_assignment" "aks_workload_identity_storage_account_access" {
  for_each = { for r in var.region_settings : r.name => r }
  principal_id = azurerm_user_assigned_identity.workload_identity[each.value.name].principal_id
  role_definition_name = "Storage Queue Data Contributor"
  scope = azurerm_storage_account.storage_account[each.value.name].id
}

## import exsting shared storage for model storage across all regions
data "azurerm_storage_account" "shared_storage_account" {
  name = var.shared_storage.name
  resource_group_name = var.shared_storage.resource_group_name
}

# # create container for model storage, assume this is already created manually
# resource "azurerm_storage_container" "model_storage_container" {
#   name                  = "model-storage"
#   storage_account_id    = data.azurerm_storage_account.shared_storage_account.id
# }

# grant access to aks workload identity to make sure application pod can access model storage
resource "azurerm_role_assignment" "aks_workload_identity_shared_storage_access" {
  for_each = { for r in var.region_settings : r.name => r }
  principal_id = azurerm_user_assigned_identity.workload_identity[each.value.name].principal_id
  role_definition_name = "Storage Blob Data Contributor"
  scope = data.azurerm_storage_account.shared_storage_account.id
}

# grant access to aks node pool identity to make sure node can access model storage
resource "azurerm_role_assignment" "aks_managed_identity_shared_storage_access" {
  for_each = { for r in var.region_settings : r.name => r }
  principal_id = azurerm_kubernetes_cluster.aks[each.value.name].kubelet_identity[0].object_id
  role_definition_name = "Storage Blob Data Contributor"
  scope = data.azurerm_storage_account.shared_storage_account.id
}