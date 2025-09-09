# create per region vmss user data using cloud-init

locals {
  upload_server_vmss_user_data = {
    for region in var.region_settings :
    region.name => templatefile(
      "${path.module}/upload-server.cloud-init.tpl",
      {
        region_name = region.name
        region_short_name = region.short_name
        upload_server_container_url = var.upload_server_container_url
        acr_resource_id = var.azure_container_registry_id
      }
    )
  }

  upload_server_vmss_default_instances = 1
  # upload_server_vmss_default_vm_size = "Standard_D2als_v6"
}


# create upload servervmss for using ubuntu image ,
# use vmss sku from region_settings, otherwise use default sku
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  for_each = { for r in var.region_settings : r.name => r }
  depends_on = [ azurerm_lb_probe.upload_server_lb_probe ,azurerm_lb.upload_server_lb, azurerm_lb_rule.upload_server_lb_rule_https ]

  name                = "vmss-upload-server-${each.key}"
  resource_group_name = azurerm_resource_group.rg[each.value.name].name
  location            = each.value.name
  sku                 = each.value.upload_server_vmss_sku
  instances           = local.upload_server_vmss_default_instances

  admin_username      = "ubuntu"

  admin_ssh_key {
    username   = "ubuntu"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  boot_diagnostics {
    storage_account_uri = ""   # enable and use managed storage for boot diagnostics
  }

  identity {
    type = "SystemAssigned"
  }

  # priority = "Spot"
  # eviction_policy = "Delete"
  # max_bid_price = "-1"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 32
  }

  network_interface {
    name    = "vmss-nic"
    primary = true
    ip_configuration {
      name                          = "internal"
      primary                       = true
      subnet_id                     = azurerm_subnet.public_subnet[each.value.name].id
     # add both public and internal lb backend address pool id
      load_balancer_backend_address_pool_ids = [
                  azurerm_lb_backend_address_pool.upload_server_internal_lb_backend_address_pool[each.value.name].id,
                  azurerm_lb_backend_address_pool.upload_server_lb_backend_address_pool[each.value.name].id
                ]
      public_ip_address {
        name = "vmss-public-ip"
      }
    }
  }

  #source_image_id = var.upload_server_vmss_image_id

  # # az vm image list --all -l southeastasia --publisher Canonical
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  user_data = base64encode(local.upload_server_vmss_user_data[each.value.name])

#  zones = ["1", "2", "3"]
#  zone_balance = true

  # enable automatic instance repair after 10 minutes, using http probe /health
  # health_probe_id = azurerm_lb_probe.upload_server_lb_probe[each.value.name].id
  health_probe_id = azurerm_lb_probe.upload_server_internal_lb_probe[each.value.name].id
  # don't perform automatic upgrade
  upgrade_mode = "Manual"

  # enable automatic instance repair after 10 minutes, using http probe /health
  automatic_instance_repair {
    enabled = true
    grace_period = "PT10M"
    action = "Replace"
  }

  termination_notification {
    enabled = true
    timeout = "PT10M"
    # 10min notification before instance is delete
  }

  scale_in {
    # rule = "OldestVM"
    rule = "Default"   # let vmss choice the best vm to scale in
    force_deletion_enabled = false
  }

  # Ignore changes to instances since we have autoscaling policy
  lifecycle {
    ignore_changes = [
      instances
    ]
  }
}

# create vmss auto scale rule
resource "azurerm_monitor_autoscale_setting" "vmss_auto_scale" {
  for_each = { for r in var.region_settings : r.name => r }

  name                = "vmss-auto-scale-cz-vmss-demo"
  resource_group_name = azurerm_resource_group.rg[each.value.name].name
  location            = each.value.name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss[each.value.name].id

  profile {
    name = "defaultProfile"

    capacity {
      default = 1
      minimum = 1
      maximum = 20
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss[each.value.name].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
        metric_namespace   = "microsoft.compute/virtualmachinescalesets"
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss[each.value.name].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 60
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT2M"
      }
    }
  }

  # predictive {
  #   scale_mode      = "Enabled"
  #   look_ahead_time = "PT5M"
  # }

  # notification {
  #   email {
  #     # send_to_subscription_administrator    = true
  #     # send_to_subscription_co_administrator = true
  #     custom_emails                         = ["zhen.chen@microsoft.com"]
  #   }
  # }
}

# 获取所有 VMSS 实例
data "azurerm_virtual_machine_scale_set" "vmss_vms" {
  for_each = { for r in var.region_settings : r.name => r }
  name = azurerm_linux_virtual_machine_scale_set.vmss[each.value.name].name
  resource_group_name = azurerm_resource_group.rg[each.value.name].name
}

# 输出
output "vm_names_and_public_ips" {
  value = { for r in var.region_settings : r.name =>
    [for vm in data.azurerm_virtual_machine_scale_set.vmss_vms[r.name].instances :
    "${vm.computer_name}, ${try(vm.public_ip_address, "no public ip")}"
    ]
  }
}

## rbac settings to allow vmss to access container registry
resource "azurerm_role_assignment" "vmss_container_registry_access" {
  for_each = { for r in var.region_settings : r.name => r }
  depends_on = [ azurerm_linux_virtual_machine_scale_set.vmss ]

  principal_id = azurerm_linux_virtual_machine_scale_set.vmss[each.value.name].identity[0].principal_id
  role_definition_name = "AcrPull"
  scope = var.azure_container_registry_id
}

## 为所有区域的所有 VMSS 授予所有区域存储账户的 blob 存储访问权限
## 现在每个 region 有一个 vmss， 每个 region 有一个 storage account，需要 vmss 可以访问所有region 的storage account

resource "azurerm_role_assignment" "vmss_blob_storage_access_all" {
  for_each = {
    for pair in setproduct(keys({ for r in var.region_settings : r.name => r }), keys({ for r in var.region_settings : r.name => r })) :
    "${pair[0]}-${pair[1]}" => {
      vmss_region = pair[0]
      storage_region = pair[1]
      vmss_principal_id = azurerm_linux_virtual_machine_scale_set.vmss[pair[0]].identity[0].principal_id
    }
  }

  depends_on = [ azurerm_linux_virtual_machine_scale_set.vmss ]

  principal_id         = each.value.vmss_principal_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.storage_account[each.value.storage_region].id
}
