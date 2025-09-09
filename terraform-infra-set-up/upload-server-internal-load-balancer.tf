# 创建一个私有负载均衡器（Private Load Balancer），与 VMSS 放在同一个子网
resource "azurerm_lb" "upload_server_internal_lb" {
  for_each = { for r in var.region_settings : r.name => r }

  name                = "lb-upload-server-internal-${each.key}"
  resource_group_name = azurerm_resource_group.rg[each.value.name].name
  location            = each.value.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "internal"
    subnet_id            = azurerm_subnet.public_subnet[each.value.name].id
    private_ip_address_allocation = "Dynamic"
  }
}

# create a backend address pool for upload server vmss
resource "azurerm_lb_backend_address_pool" "upload_server_internal_lb_backend_address_pool" {
  for_each = { for r in var.region_settings : r.name => r }

  name = "lb-upload-server-internal-${each.key}-backend-address-pool"
  loadbalancer_id = azurerm_lb.upload_server_internal_lb[each.value.name].id
}

# create http probe for upload server vmss
resource "azurerm_lb_probe" "upload_server_internal_lb_probe" {
  for_each = { for r in var.region_settings : r.name => r }

  name = "lb-upload-server-internal-${each.key}-probe"
  loadbalancer_id = azurerm_lb.upload_server_internal_lb[each.value.name].id
  port = 443
  protocol = "Https"
  request_path = "/health"
}

# create a load balancer rule for upload server vmss to http 80 and https 443
resource "azurerm_lb_rule" "upload_server_internal_lb_rule_http" {
  for_each = { for r in var.region_settings : r.name => r }

  name = "lb-upload-server-internal-${each.key}-rule"
  loadbalancer_id = azurerm_lb.upload_server_internal_lb[each.value.name].id
  frontend_ip_configuration_name = "internal"
  backend_port = 80
  frontend_port = 80
  protocol = "Tcp"
  probe_id = azurerm_lb_probe.upload_server_internal_lb_probe[each.value.name].id
  disable_outbound_snat = true
  backend_address_pool_ids = [azurerm_lb_backend_address_pool.upload_server_internal_lb_backend_address_pool[each.value.name].id]
}

resource "azurerm_lb_rule" "upload_server_internal_lb_rule_https" {
  for_each = { for r in var.region_settings : r.name => r }

  name = "lb-upload-server-internal-${each.key}-rule-https"
  loadbalancer_id = azurerm_lb.upload_server_internal_lb[each.value.name].id
  frontend_ip_configuration_name = "internal"
  backend_port = 443
  frontend_port = 443
  protocol = "Tcp"
  probe_id = azurerm_lb_probe.upload_server_internal_lb_probe[each.value.name].id
  disable_outbound_snat = true
  backend_address_pool_ids = [azurerm_lb_backend_address_pool.upload_server_internal_lb_backend_address_pool[each.value.name].id]
}


# output lb private_ip
output "lb_private_ip" {
  value = { for r in var.region_settings : r.name => azurerm_lb.upload_server_internal_lb[r.name].frontend_ip_configuration[0].private_ip_address }
}

### create private link service for this lb to allow azure front door to access the lb
resource "azurerm_private_link_service" "pls_upload_server_internal" {
  for_each            = { for r in var.region_settings : r.name => r }
  name                = "pls-upload-server-internal-${each.value.short_name}"
  resource_group_name = azurerm_resource_group.rg[each.value.name].name
  location            = azurerm_resource_group.rg[each.value.name].location

  load_balancer_frontend_ip_configuration_ids = [azurerm_lb.upload_server_internal_lb[each.value.name].frontend_ip_configuration[0].id]

  nat_ip_configuration {
    name                       = "primary"
    private_ip_address_version = "IPv4"
    subnet_id                  = azurerm_subnet.public_subnet[each.value.name].id
    primary                    = true
  }

  nat_ip_configuration {
    name                       = "secondary"
    private_ip_address_version = "IPv4"
    subnet_id                  = azurerm_subnet.public_subnet[each.value.name].id
    primary                    = false
  }

  nat_ip_configuration {
    name                       = "third"
    private_ip_address_version = "IPv4"
    subnet_id                  = azurerm_subnet.public_subnet[each.value.name].id
    primary                    = false
  }
}
