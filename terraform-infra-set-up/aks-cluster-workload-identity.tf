# create aad pod identity for each aks cluster
resource "azurerm_user_assigned_identity" "workload_identity" {
  for_each = { for r in var.region_settings : r.name => r }
  name                = "aks-cluster-workload-identity-${each.value.short_name}"
  resource_group_name = azurerm_resource_group.rg[each.value.name].name
  location            = each.value.name
}

# Assign "Monitoring Data Reader" role to workload identity
# this will be used for KEDA to read metrics from prometheus later on
resource "azurerm_role_assignment" "workload_identity_monitoring_data_reader" {
  for_each = { for r in var.region_settings : r.name => r }
  principal_id = azurerm_user_assigned_identity.workload_identity[each.value.name].principal_id
  role_definition_name = "Monitoring Data Reader"
  scope = azurerm_monitor_workspace.prometheus.id
}

# create keda cluster trigger auth yaml for each region
locals {
   keda_cluster_trigger_auth_yamls = {
    for region in var.region_settings : region.name => templatefile(
      "${path.module}/../aks-karpenter/keda-clustertriggerauth.yaml.tpl",
      {
        USER_ASSIGNED_CLIENT_ID = azurerm_user_assigned_identity.workload_identity[region.name].client_id
      }
    )
  }
}

# save keda cluster trigger auth yaml to local file
resource "local_file" "keda_cluster_trigger_auth_yaml" {
  for_each = local.keda_cluster_trigger_auth_yamls

  content     = each.value
  filename    = "${path.module}/../aks-karpenter/keda-clustertriggerauth-${each.key}.yaml"
}

# apply keda cluster trigger auth yaml to each aks cluster
resource "null_resource" "apply_keda_cluster_trigger_auth" {
  for_each = local.keda_cluster_trigger_auth_yamls

  depends_on = [ time_sleep.wait_2_minutes, local_file.kubeconfig, local_file.keda_cluster_trigger_auth_yaml ]

  triggers = {
    yaml_hash  = filesha1("../aks-karpenter/keda-clustertriggerauth.yaml.tpl")
    kubeconfig = local_file.kubeconfig[each.key].filename
    yaml_path  = local_file.keda_cluster_trigger_auth_yaml[each.key].filename
  }

  provisioner "local-exec" {
    command = "kubectl apply -f ${self.triggers.yaml_path}"
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
}

# Define namespaces where we want to create workload identity service accounts
locals {
  workload_identity_namespaces = var.workload_identity_namespaces

  # 为每个区域和命名空间组合创建 workload identity 配置
  workload_identity_configs = flatten([
    for region in var.region_settings : [
      for namespace in local.workload_identity_namespaces : {
        region_name = region.name
        region_short_name = region.short_name
        namespace = namespace
        service_account_name = "workload-identity"
        client_id = azurerm_user_assigned_identity.workload_identity[region.name].client_id
      }
    ]
  ])
}

# create workload identity service account yaml for each region and namespace
locals {
  workload_identity_service_account_yamls = {
    for config in local.workload_identity_configs :
    "${config.region_name}-${config.namespace}" => templatefile(
      "${path.module}/../aks-karpenter/pod-workload-identity.yaml.tpl",
      {
        USER_ASSIGNED_CLIENT_ID = config.client_id
        SERVICE_ACCOUNT_NAME = config.service_account_name
        SERVICE_ACCOUNT_NAMESPACE = config.namespace
      }
    )
  }
}

# create federated identity credential for each region and namespace
resource "azurerm_federated_identity_credential" "workload_identity_federated_credential" {
  for_each = { for config in local.workload_identity_configs : "${config.region_name}-${config.namespace}" => config }

  name                = "workload-identity-federated-credential-${each.value.region_short_name}-${each.value.namespace}"
  resource_group_name = azurerm_resource_group.rg[each.value.region_name].name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks[each.value.region_name].oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.workload_identity[each.value.region_name].id
  subject             = "system:serviceaccount:${each.value.namespace}:${each.value.service_account_name}"
}

# create federated identity credential for each region 'system:serviceaccount:kube-system:keda-operator'
resource "azurerm_federated_identity_credential" "workload_identity_federated_credential_keda_operator" {
  for_each            = { for r in var.region_settings : r.name => r }
  depends_on          = [ azurerm_user_assigned_identity.workload_identity ]

  name                = "workload-identity-federated-credential-${each.value.short_name}-keda-operator"
  resource_group_name = azurerm_resource_group.rg[each.value.name].name

  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks[each.value.name].oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.workload_identity[each.value.name].id
  subject             = "system:serviceaccount:kube-system:keda-operator"
}

# save workload identity service account yaml to local file
resource "local_file" "workload_identity_service_account_yaml" {
  for_each = local.workload_identity_service_account_yamls

  content     = each.value
  filename    = "${path.module}/../aks-karpenter/pod-workload-identity-${each.key}.yaml"
}

# apply yaml to each aks cluster to create service account
resource "null_resource" "apply_workload_identity_service_account" {
  for_each = local.workload_identity_service_account_yamls

  depends_on = [ time_sleep.wait_2_minutes, local_file.kubeconfig ]

  triggers = {
    yaml_hash  = filesha1("../aks-karpenter/pod-workload-identity.yaml.tpl")
    kubeconfig = local_file.kubeconfig[split("-", each.key)[0]].filename
    yaml_path  = local_file.workload_identity_service_account_yaml[each.key].filename
  }

  provisioner "local-exec" {
    command = "kubectl apply -f ${self.triggers.yaml_path}"
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
}

## create keda trigger authentication for each region and namespace
locals {
  keda_trigger_authentication_yamls = {
    for config in local.workload_identity_configs :
    "${config.region_name}-${config.namespace}" => templatefile(
      "${path.module}/../aks-karpenter/keda-triggerauth.yaml.tpl",
      {
        NAMESPACE = config.namespace
        USER_ASSIGNED_CLIENT_ID = config.client_id
      }
    )
  }
}

# save keda trigger authentication yaml to local file
resource "local_file" "keda_trigger_authentication_yaml" {
  for_each = local.keda_trigger_authentication_yamls

  content     = each.value
  filename    = "${path.module}/../aks-karpenter/keda-triggerauth-${each.key}.yaml"
}

# apply yaml to each aks cluster to create trigger authentication
resource "null_resource" "apply_keda_trigger_authentication" {
  for_each = local.keda_trigger_authentication_yamls

  depends_on = [ time_sleep.wait_2_minutes, local_file.kubeconfig, local_file.keda_trigger_authentication_yaml ]

  triggers = {
    yaml_hash  = filesha1("../aks-karpenter/keda-triggerauth.yaml.tpl")
    kubeconfig = local_file.kubeconfig[split("-", each.key)[0]].filename
    yaml_path  = local_file.keda_trigger_authentication_yaml[each.key].filename
  }

  provisioner "local-exec" {
    command = "kubectl apply -f ${self.triggers.yaml_path}"
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
}


## 为区域aks workload identity 授予所有区域存储账户的 blob 存储访问权限
## 现在每个 region 有一个 aks workload identity
## 每个 region 有一个 storage account，需要 aks workload identity 可以访问所有region 的storage account
resource "azurerm_role_assignment" "aks_workload_identity_blob_storage_access_all" {
  for_each = {
    for pair in setproduct(keys({ for r in var.region_settings : r.name => r }), keys({ for r in var.region_settings : r.name => r })) :
    "${pair[0]}-${pair[1]}" => {
      aks_region = pair[0]
      storage_region = pair[1]
      aks_workload_identity_principal_id = azurerm_user_assigned_identity.workload_identity[pair[0]].principal_id
    }
  }

  depends_on = [ azurerm_user_assigned_identity.workload_identity ]

  principal_id         = each.value.aks_workload_identity_principal_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.storage_account[each.value.storage_region].id
}