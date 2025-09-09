# apply yaml to all aks clusters make sure this will re-apply every time when yaml changes
# enable metrics for app routing addon (nginx based ingress)
# pod-annotation-based-scraping is enabled for all namespaces using this ConfigMap
resource "null_resource" "apply_yaml_ingress_metrics" {
  for_each = { for r in var.region_settings : r.name => r }
  depends_on = [time_sleep.wait_2_minutes, local_file.kubeconfig]

  triggers = {
    yaml_hash  = filesha1("../aks-karpenter/aks-monitoring-cm.yaml")
    kubeconfig = local_file.kubeconfig[each.key].filename
    yaml_path  = "../aks-karpenter/aks-monitoring-cm.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl apply -f ${self.triggers.yaml_path}"
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
}

# 创建内网 ip 的 web app routing ingress
resource "null_resource" "apply_yaml_nginx_ingress_internal" {
  for_each = { for r in var.region_settings : r.name => r }
  depends_on = [time_sleep.wait_2_minutes, local_file.kubeconfig]

  triggers = {
    yaml_hash  = filesha1("../aks-karpenter/aks-nginx-ingress-public.yaml")
    kubeconfig = local_file.kubeconfig[each.key].filename
    yaml_path  = "../aks-karpenter/aks-nginx-ingress-public.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl apply -f ${self.triggers.yaml_path}"
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
}

# 使用 az 命令工具导入 nginx dashbroad
# az config set extension.use_dynamic_install=yes_without_prompt
# run this command to install az extension for Azure Managed Grafana
# az extension add --name amg
# using az grafana import to import nginx dashboard
resource "null_resource" "import_az_extension_amg" {
  depends_on = [azurerm_dashboard_grafana.grafana]

  provisioner "local-exec" {
    command = "az extension add --name amg"
  }
}

# using az grafana import to import nginx dashboard
# https://grafana.com/grafana/dashboards/21336-nginx-ingress-controller/
# dashboard id is 21336
# dashboard name is Nginx Ingress Controller
resource "null_resource" "import_nginx_dashboard" {
  depends_on = [azurerm_dashboard_grafana.grafana, null_resource.import_az_extension_amg]

  triggers = {
    grafana_status = jsonencode(azurerm_dashboard_grafana.grafana)
    grafana_id = 21336
  }

  provisioner "local-exec" {
    command = <<EOT
az grafana dashboard import -n ${azurerm_dashboard_grafana.grafana.name} -g ${azurerm_resource_group.monitoring.name} --definition ${self.triggers.grafana_id} --overwrite true
EOT
  }
}

# using az grafana import to import request handling performancedashboard
# dashboard id is 16677
# dashboard name is Ingress Nginx Overview
# https://grafana.com/grafana/dashboards/16677-ingress-nginx-overview/
resource "null_resource" "import_nginx_dashboard_overview" {
  depends_on = [azurerm_dashboard_grafana.grafana, null_resource.import_az_extension_amg]

  triggers = {
    grafana_status = jsonencode(azurerm_dashboard_grafana.grafana)
    grafana_id = 16677
  }

  provisioner "local-exec" {
    command = <<EOT
az grafana dashboard import -n ${azurerm_dashboard_grafana.grafana.name} -g ${azurerm_resource_group.monitoring.name} --definition ${self.triggers.grafana_id} --overwrite true
EOT
  }
}

# assign "Network Contributor" role to web app routing identity
resource "azurerm_role_assignment" "web_app_routing_network_contributor" {
  for_each = { for r in var.region_settings : r.name => r }
  
  principal_id = azurerm_kubernetes_cluster.aks[each.value.name].web_app_routing[0].web_app_routing_identity[0].object_id
  role_definition_name = "Network Contributor"
  scope = azurerm_resource_group.rg[each.value.name].id
}


# #######
# manual import dashboard using below command 
# #######

# az grafana dashboard import -n zr-test -g corp_name-monitoring --definition 16677 --overwrite true
# az grafana dashboard import -n zr-test -g corp_name-monitoring --definition 21336 --overwrite true


