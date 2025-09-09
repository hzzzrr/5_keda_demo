resource "azurerm_public_ip" "upload_server_lb_public_ip" {
  for_each = { for r in var.region_settings : r.name => r }

  name = "lb-upload-server-${each.key}-public-ip"
  resource_group_name = azurerm_resource_group.rg[each.value.name].name
  location = each.value.name
  allocation_method = "Static"
  sku = "Standard"
}

# 创建一个私有负载均衡器（Private Load Balancer），与 VMSS 放在同一个子网
resource "azurerm_lb" "upload_server_lb" {
  for_each = { for r in var.region_settings : r.name => r }

  name                = "lb-upload-server-${each.key}"
  resource_group_name = azurerm_resource_group.rg[each.value.name].name
  location            = each.value.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "public"
#     subnet_id            = azurerm_subnet.public_subnet[each.value.name].id
#     private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.upload_server_lb_public_ip[each.value.name].id
  }
}

# create a backend address pool for upload server vmss
resource "azurerm_lb_backend_address_pool" "upload_server_lb_backend_address_pool" {
  for_each = { for r in var.region_settings : r.name => r }

  name = "lb-upload-server-${each.key}-backend-address-pool"
  loadbalancer_id = azurerm_lb.upload_server_lb[each.value.name].id
}

# create http probe for upload server vmss
resource "azurerm_lb_probe" "upload_server_lb_probe" {
  for_each = { for r in var.region_settings : r.name => r }

  name = "lb-upload-server-${each.key}-probe"
  loadbalancer_id = azurerm_lb.upload_server_lb[each.value.name].id
  port = 443
  protocol = "Https"
  request_path = "/health"
}

# create a load balancer rule for upload server vmss to http 80 and https 443
resource "azurerm_lb_rule" "upload_server_lb_rule_http" {
  for_each = { for r in var.region_settings : r.name => r }

  name = "lb-upload-server-${each.key}-rule"
  loadbalancer_id = azurerm_lb.upload_server_lb[each.value.name].id
  frontend_ip_configuration_name = "public"
  backend_port = 80
  frontend_port = 80
  protocol = "Tcp"
  probe_id = azurerm_lb_probe.upload_server_lb_probe[each.value.name].id
  disable_outbound_snat = true
  backend_address_pool_ids = [azurerm_lb_backend_address_pool.upload_server_lb_backend_address_pool[each.value.name].id]
}

resource "azurerm_lb_rule" "upload_server_lb_rule_https" {
  for_each = { for r in var.region_settings : r.name => r }

  name = "lb-upload-server-${each.key}-rule-https"
  loadbalancer_id = azurerm_lb.upload_server_lb[each.value.name].id
  frontend_ip_configuration_name = "public"
  backend_port = 443
  frontend_port = 443
  protocol = "Tcp"
  probe_id = azurerm_lb_probe.upload_server_lb_probe[each.value.name].id
  disable_outbound_snat = true
  backend_address_pool_ids = [azurerm_lb_backend_address_pool.upload_server_lb_backend_address_pool[each.value.name].id]
}


# output lb private_ip
output "upload_server_lb_public_ip" {
  value = { for r in var.region_settings : r.name => azurerm_public_ip.upload_server_lb_public_ip[r.name].ip_address }
}

