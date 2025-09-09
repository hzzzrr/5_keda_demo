
# 创建一个配置数据，定一个region列表，每个region对应不同的参数配置，比如vnet地址空间网段
variable "region_settings" {
  description = "Regions with settings"

  type = list(object({
    name          = string,
    short_name    = string,
    vnet_address_spaces = list(string),
    vm_subnet_address_spaces = list(string),
    aks_subnet_address_spaces = list(string),
    pod_subnet_address_spaces = list(string),
    public_subnet_address_spaces = list(string),
    vhub_address_space = string,
    upload_server_vmss_sku = string
  }))
}

variable "primary_region" {
  description = "Primary region"
  type        = string
}

#input sub id for this deployment
variable "subscription-id" {
  type = string
}

variable "rg_name_prefix" {
  description = "Resource group name prefix"
  type        = string
}

variable "storage_account_name_prefix" {
  description = "Storage account name prefix"
  type        = string
}

variable "key_vault_name" {
  description = "Key vault name"
  type        = string
}

variable "tenant-id" { 
  description = "Tenant ID"
  type        = string
}

variable "azure_container_registry_id" {
  description = "Azure container registry id"
  type        = string
}

variable "upload_server_vmss_image_id" {
  description = "Upload server vmss image id"
  type        = string
  default     = ""  # modifie
}

variable "upload_server_container_url" {
  description = "Upload server container user"
  type        = string
}

variable "workload_identity_namespaces" {
  description = "Namespaces where workload identity service accounts should be created"
  type        = list(string)
  default     = ["default", "kube-system"]
}

variable "grafana_name" {
  description = "Grafana name"
  type        = string
}

variable "redis_name_prefix" {
  description = "Azure Managed Redis name prefix"
  type        = string
}

variable "shared_storage" {
  description = "Shared storage account"
  type        = object({
    name = string,
    resource_group_name = string
  })
}