locals {
  redis = {
    sku = "Balanced_B0"
    private_dns_zone_name = "privatelink.redis.azure.net"
  }
}

# create resource group for all private dns zone
resource "azurerm_resource_group" "private_dns_zone_rg" {
  name     = "corp-private-dns-zone"
  location = var.primary_region
}

# create private dns zone in primary region for azure managed redis
resource "azurerm_private_dns_zone" "redis_private_dns_zone" {
  name                = local.redis.private_dns_zone_name
  resource_group_name = azurerm_resource_group.private_dns_zone_rg.name
}

# create private dns zone link for vnet in each region
resource "azurerm_private_dns_zone_virtual_network_link" "redis_private_dns_zone_link" {
  for_each  = { for r in var.region_settings : r.name => r }

  name      = "nvs-redis-private-dns-zone-link-${each.value.short_name}"
  private_dns_zone_name = azurerm_private_dns_zone.redis_private_dns_zone.name
  virtual_network_id = azurerm_virtual_network.vnet[each.value.name].id
  resource_group_name = azurerm_resource_group.private_dns_zone_rg.name

  depends_on = [
    azurerm_private_dns_zone.redis_private_dns_zone
  ]
}

# create private endpoint for redis in each region
resource "azurerm_private_endpoint" "redis_private_endpoint" {
  for_each  = { for r in var.region_settings : r.name => r }
  
  name      = "nvs-redis-private-endpoint-${each.value.short_name}"
  location  = each.value.name
  resource_group_name = azurerm_resource_group.rg[each.value.name].name
  subnet_id = azurerm_subnet.vm_subnet[each.value.name].id # use vm subnet for private endpoint   

  private_service_connection {
    name = "nvs-redis-private-service-connection-${each.value.short_name}"
    private_connection_resource_id = azapi_resource.azure_managed_redis[each.value.name].id
    is_manual_connection = false
    subresource_names = ["redisEnterprise"]
  }

  private_dns_zone_group {
    name                 = "nvs-redis-private-dns-zone-group-${each.value.short_name}"
    private_dns_zone_ids = [azurerm_private_dns_zone.redis_private_dns_zone.id]
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.redis_private_dns_zone_link
  ]
}

# Azure Managed Redis for each region
# currently azure provider is not supported for Azure Managed Redis, 
# so we use azapi to create it
resource "azapi_resource" "azure_managed_redis" {
  for_each  = { for r in var.region_settings : r.name => r }

  type      = "Microsoft.Cache/redisEnterprise@2025-04-01"
  name      = "${var.redis_name_prefix}-${each.value.short_name}"
  location  = each.value.name
  parent_id = azurerm_resource_group.rg[each.value.name].id

  body = {
    properties = {
      highAvailability = "Enabled",
    }
    sku = {
      name = local.redis.sku
    }
  }

  schema_validation_enabled = false
}

# create redis db for each regoin
# run below command to update azapi resource
# terraform taint 'azapi_resource.amr_db["eastus2"]'

resource "azapi_resource" "amr_db" {
  for_each  = { for r in var.region_settings : r.name => r }

  type = "Microsoft.Cache/redisEnterprise/databases@2025-04-01"
  name = "default"
  parent_id = azapi_resource.azure_managed_redis[each.value.name].id
  depends_on =  [azapi_resource.azure_managed_redis] 

  body = {
    properties = {
      accessKeysAuthentication = "Enabled"
      # clientProtocol = "Encrypted"
      clientProtocol = "Plaintext"
      port = 10000
      # clusteringPolicy = "OSSCluster"        
      clusteringPolicy = "EnterpriseCluster" 
      deferUpgrade = "Deferred"
      evictionPolicy = "VolatileLRU"
      persistence = {
        aofEnabled    = true
        aofFrequency  = "1s"
        #rdbEnabled   = false
        #rdbFrequency = "6h"
      }
    #   modules = [for module in var.modules_enabled : {
    #     name = module
    #   }]
    }
  }
}

