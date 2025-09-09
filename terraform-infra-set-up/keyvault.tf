# 在主region创建azure key vault
resource "azurerm_key_vault" "key_vault" {
  name                = var.key_vault_name
  location            = var.primary_region
  resource_group_name = azurerm_resource_group.rg[var.primary_region].name
  sku_name            = "standard"

  tenant_id           = var.tenant-id
  enable_rbac_authorization = true
}

# add rbac for aks mi to access keyvault
resource "azurerm_role_assignment" "aks_mi_keyvault_access" {
  for_each = { for r in var.region_settings : r.name => r }
  principal_id = azurerm_kubernetes_cluster.aks[each.value.name].kubelet_identity[0].object_id
  role_definition_name = "Key Vault Secrets User"
  scope = azurerm_key_vault.key_vault.id
}

# add rbac for aks workload identity to access keyvault, application pod will use workload identity as well
resource "azurerm_role_assignment" "aks_workload_identity_keyvault_access" {
  for_each = { for r in var.region_settings : r.name => r }
  principal_id = azurerm_user_assigned_identity.workload_identity[each.value.name].principal_id
  role_definition_name = "Key Vault Secrets User"
  scope = azurerm_key_vault.key_vault.id
}