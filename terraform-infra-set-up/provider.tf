terraform {
  required_providers {
    # azurerm Provider 用来管理和创建azure资源
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.39.0"
    }

    # local Provider 用来创建本地文件，写入kubeconfig文件等
    local = {
      source = "hashicorp/local"
      version = "2.5.2"
    }

    # 引入azapi provider直接调用azure api， 用于更新aks cluster的node provisioning profile
    azapi = {
      source = "azure/azapi"
      version = "2.6.0"
    }

    # 引入time provider， 用于等待资源创建完成
    time = {
      source = "hashicorp/time"
      version = "0.13.1"
    }

    null = {
      source = "hashicorp/null"
      version = "3.2.4"
    }
  }

  # 使用azure backend， 使用azurerm provider来管理tfstate文件， 需要提前创建好storage account container和resource group
  backend "azurerm" {
  }
  
}

provider "azapi" {
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.subscription-id
  
  # 使用Azure AD身份验证
  storage_use_azuread = true
}

