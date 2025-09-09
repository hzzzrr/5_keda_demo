# create full mesh vnet peering between all vnets

locals {
  vnet_names = [for k in keys(azurerm_virtual_network.vnet) : k]
  vnet_pairs = flatten([
    for i, a in local.vnet_names :
    [for j in range(i+1, length(local.vnet_names)) : { from = a, to = local.vnet_names[j] }]
  ])
}

resource "azurerm_virtual_network_peering" "peering" {
  depends_on = [azurerm_virtual_network.vnet]
  for_each = {
    for pair in local.vnet_pairs :
    "${pair.from}-${pair.to}" => {
      source_vnet_key = pair.from
      remote_vnet_key = pair.to
    }
  }

  name                      = "peer-${each.value.source_vnet_key}-to-${each.value.remote_vnet_key}"
  resource_group_name       = azurerm_virtual_network.vnet[each.value.source_vnet_key].resource_group_name
  virtual_network_name      = azurerm_virtual_network.vnet[each.value.source_vnet_key].name
  remote_virtual_network_id = azurerm_virtual_network.vnet[each.value.remote_vnet_key].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "peering_reverse" {
  for_each = {
    for pair in local.vnet_pairs :
    "${pair.to}-${pair.from}" => {
      source_vnet_key = pair.to
      remote_vnet_key = pair.from
    }
  }

  name                      = "peer-${each.value.source_vnet_key}-to-${each.value.remote_vnet_key}"
  resource_group_name       = azurerm_virtual_network.vnet[each.value.source_vnet_key].resource_group_name
  virtual_network_name      = azurerm_virtual_network.vnet[each.value.source_vnet_key].name
  remote_virtual_network_id = azurerm_virtual_network.vnet[each.value.remote_vnet_key].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}