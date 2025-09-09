# 创建vnet, 每个region 用一个vnet，使用region_settings 中的address_space,
resource "azurerm_virtual_network" "vnet" {
  for_each            = { for r in var.region_settings : r.name => r }
  name                = "vnet-${each.key}"
  location            = each.value.name
  resource_group_name = azurerm_resource_group.rg[each.value.name].name
  address_space       = each.value.vnet_address_spaces
}

# 创建vm subnet
resource "azurerm_subnet" "vm_subnet" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "vm-subnet-${each.key}"
  virtual_network_name          = azurerm_virtual_network.vnet[each.value.name].name
  resource_group_name           = azurerm_resource_group.rg[each.value.name].name
  address_prefixes              = each.value.vm_subnet_address_spaces

  service_endpoints = ["Microsoft.Storage"]
}

#创建aks subnet
resource "azurerm_subnet" "aks_subnet" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "aks-subnet-${each.key}"
  virtual_network_name          = azurerm_virtual_network.vnet[each.value.name].name
  resource_group_name           = azurerm_resource_group.rg[each.value.name].name
  address_prefixes              = each.value.aks_subnet_address_spaces

  service_endpoints = ["Microsoft.Storage"]
}

#创建pod subnet
resource "azurerm_subnet" "pod_subnet" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "pod-subnet-${each.key}"
  virtual_network_name          = azurerm_virtual_network.vnet[each.value.name].name
  resource_group_name           = azurerm_resource_group.rg[each.value.name].name
  address_prefixes              = each.value.pod_subnet_address_spaces

  delegation {
    name = "aks-delegation"

    service_delegation {
      name    = "Microsoft.ContainerService/managedClusters"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  service_endpoints = ["Microsoft.Storage"]
}

#创建公网subnet，用于部署有公网ip的vmss(upload-server)
resource "azurerm_subnet" "public_subnet" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "public-subnet-${each.key}"
  virtual_network_name          = azurerm_virtual_network.vnet[each.value.name].name
  resource_group_name           = azurerm_resource_group.rg[each.value.name].name
  address_prefixes              = each.value.public_subnet_address_spaces

  private_link_service_network_policies_enabled = false
  service_endpoints = ["Microsoft.Storage"]
}

# 在每个区域创建NAT Gateway并且绑定到vnet
resource "azurerm_public_ip" "nat_gateway_public_ip" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "nat-gateway-public-ip-${each.key}"
  location                      = each.value.name
  resource_group_name           = azurerm_resource_group.rg[each.value.name].name
  sku                           = "Standard"
  allocation_method             = "Static"
}

resource "azurerm_nat_gateway" "nat_gateway" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "nat-gateway-${each.key}"
  location                      = each.value.name
  resource_group_name           = azurerm_resource_group.rg[each.value.name].name
}

# 绑定public ip到各自region的nat gateway
resource "azurerm_nat_gateway_public_ip_association" "nat_gateway_public_ip" {
  for_each                      = { for r in var.region_settings : r.name => r }
  nat_gateway_id       = azurerm_nat_gateway.nat_gateway[each.value.name].id
  public_ip_address_id = azurerm_public_ip.nat_gateway_public_ip[each.value.name].id
}

# 绑定nat gateway到各自region的subnet， 只有public subnet 不绑定nat gateway，直接使用vm public ip上网
resource "azurerm_subnet_nat_gateway_association" "vm_subnet_nat_gateway" {
  for_each                      = { for r in var.region_settings : r.name => r }
  subnet_id                     = azurerm_subnet.vm_subnet[each.value.name].id
  nat_gateway_id               = azurerm_nat_gateway.nat_gateway[each.value.name].id
}

resource "azurerm_subnet_nat_gateway_association" "aks_subnet_nat_gateway" {
  for_each                      = { for r in var.region_settings : r.name => r }
  subnet_id                     = azurerm_subnet.aks_subnet[each.value.name].id
  nat_gateway_id               = azurerm_nat_gateway.nat_gateway[each.value.name].id
}

resource "azurerm_subnet_nat_gateway_association" "pod_subnet_nat_gateway" {
  for_each                      = { for r in var.region_settings : r.name => r }
  subnet_id                     = azurerm_subnet.pod_subnet[each.value.name].id
  nat_gateway_id               = azurerm_nat_gateway.nat_gateway[each.value.name].id
}


# create nsg to allow inbound internet access to public subnet for http and https
resource "azurerm_network_security_group" "public_subnet_nsg" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "public-subnet-nsg-${each.key}"
  location                      = each.value.name
  resource_group_name           = azurerm_resource_group.rg[each.value.name].name
}

resource "azurerm_network_security_rule" "public_subnet_nsg_rule" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "public-subnet-nsg-rule-${each.key}"
  resource_group_name           = azurerm_resource_group.rg[each.value.name].name
  network_security_group_name   = azurerm_network_security_group.public_subnet_nsg[each.value.name].name
  priority                      = 1000
  direction                     = "Inbound"
  access                        = "Allow"
  protocol                      = "Tcp"
  source_address_prefix         = "*"
  source_port_range             = "*"
  destination_address_prefixes  = azurerm_subnet.public_subnet[each.value.name].address_prefixes
  destination_port_ranges       = ["80", "443"]
}

# 2nd rule to allow ssh from internet
resource "azurerm_network_security_rule" "public_subnet_nsg_rule_ssh" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "public-subnet-nsg-rule-ssh-${each.key}"
  resource_group_name           = azurerm_resource_group.rg[each.value.name].name
  network_security_group_name   = azurerm_network_security_group.public_subnet_nsg[each.value.name].name
  priority                      = 1001
  direction                     = "Inbound"
  access                        = "Allow"
  protocol                      = "Tcp"
  source_port_range             = "*"
  destination_port_ranges       = ["5566"]
  source_address_prefix         = "Internet"
  destination_address_prefixes  = azurerm_subnet.public_subnet[each.value.name].address_prefixes
}

# bind public nsg to public subnet
resource "azurerm_subnet_network_security_group_association" "public_subnet_nsg_association" {
  for_each                      = { for r in var.region_settings : r.name => r }
  subnet_id                     = azurerm_subnet.public_subnet[each.value.name].id
  network_security_group_id     = azurerm_network_security_group.public_subnet_nsg[each.value.name].id
}

# 创建 AKS 子网的 NSG
resource "azurerm_network_security_group" "aks_subnet_nsg" {
  for_each            = { for r in var.region_settings : r.name => r }
  name                = "aks-subnet-nsg-${each.key}"
  location            = each.value.name
  resource_group_name = azurerm_resource_group.rg[each.value.name].name
}

# 为 AKS NSG 添加 HTTP (80) 入站规则
resource "azurerm_network_security_rule" "aks_subnet_nsg_rule_http" {
  for_each                     = { for r in var.region_settings : r.name => r }
  name                         = "aks-subnet-nsg-rule-http-${each.key}"
  resource_group_name          = azurerm_resource_group.rg[each.value.name].name
  network_security_group_name  = azurerm_network_security_group.aks_subnet_nsg[each.value.name].name
  priority                     = 1000
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "80"
  source_address_prefix        = "*" 
  destination_address_prefix   = "*" 

  #destination_address_prefixes = azurerm_subnet.aks_subnet[each.value.name].address_prefixes
}

# 为 AKS NSG 添加 HTTPS (443) 入站规则
resource "azurerm_network_security_rule" "aks_subnet_nsg_rule_https" {
  for_each                     = { for r in var.region_settings : r.name => r }
  name                         = "aks-subnet-nsg-rule-https-${each.key}"
  resource_group_name          = azurerm_resource_group.rg[each.value.name].name
  network_security_group_name  = azurerm_network_security_group.aks_subnet_nsg[each.value.name].name
  priority                     = 1001
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "443"
  source_address_prefix        = "*"
  destination_address_prefix   = "*" 
}

# 将 AKS NSG 关联到 AKS 子网
resource "azurerm_subnet_network_security_group_association" "aks_subnet_nsg_association" {
  for_each                 = { for r in var.region_settings : r.name => r }
  subnet_id                = azurerm_subnet.aks_subnet[each.value.name].id
  network_security_group_id = azurerm_network_security_group.aks_subnet_nsg[each.value.name].id
}