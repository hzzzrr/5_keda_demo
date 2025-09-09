# resource "azurerm_storage_data_lake_gen2_filesystem" "storage_filesystem_mvr5" {
#   for_each                      = { for r in var.region_settings : r.name => r }
#   name                          = "nvs-mvr-5-${each.value.name}"
#   storage_account_id            = azurerm_storage_account.storage_account[each.value.name].id
# }

# resource "azurerm_storage_data_lake_gen2_filesystem" "storage_filesystem_mvr10" {
#   for_each                      = { for r in var.region_settings : r.name => r }
#   name                          = "nvs-mvr-10-${each.value.name}"
#   storage_account_id            = azurerm_storage_account.storage_account[each.value.name].id
# }

# resource "azurerm_storage_data_lake_gen2_filesystem" "storage_filesystem_mvr30" {
#   for_each                      = { for r in var.region_settings : r.name => r }
#   name                          = "nvs-mvr-30-${each.value.name}"
#   storage_account_id            = azurerm_storage_account.storage_account[each.value.name].id
# }

# resource "azurerm_storage_data_lake_gen2_filesystem" "storage_filesystem_mvr60" {
#   for_each                      = { for r in var.region_settings : r.name => r }
#   name                          = "nvs-mvr-60-${each.value.name}"
#   storage_account_id            = azurerm_storage_account.storage_account[each.value.name].id
#}

### create storage account for mvr pic
resource "azurerm_storage_data_lake_gen2_filesystem" "storage_filesystem_pic5" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "nvs-pic-5-${each.value.name}"
  storage_account_id            = azurerm_storage_account.storage_account[each.value.name].id
}

# resource "azurerm_storage_data_lake_gen2_filesystem" "storage_filesystem_pic10" {
#   for_each                      = { for r in var.region_settings : r.name => r }
#   name                          = "nvs-pic-10-${each.value.name}"
#   storage_account_id            = azurerm_storage_account.storage_account[each.value.name].id
# }

# resource "azurerm_storage_data_lake_gen2_filesystem" "storage_filesystem_pic30" {
#   for_each                      = { for r in var.region_settings : r.name => r }
#   name                          = "nvs-pic-30-${each.value.name}"
#   storage_account_id            = azurerm_storage_account.storage_account[each.value.name].id
# }

# resource "azurerm_storage_data_lake_gen2_filesystem" "storage_filesystem_pic60" {
#   for_each                      = { for r in var.region_settings : r.name => r }
#   name                          = "nvs-pic-60-${each.value.name}"
#   storage_account_id            = azurerm_storage_account.storage_account[each.value.name].id
# }


# 创建storage account queue for mvr
resource "azurerm_storage_queue" "storage_queue_mvr" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "blob-event-queue-mvr-${each.value.short_name}"
  storage_account_name            = azurerm_storage_account.storage_account[each.value.name].name
}


# 在每个region创建event grid event subscription，用来触发storage queue
resource "azurerm_eventgrid_event_subscription" "event_subscription_mvr" {
  depends_on                    = [azurerm_storage_queue.storage_queue_mvr]
  for_each                      = { for r in var.region_settings : r.name => r }

  name                          = "storage-event-mvr-${each.value.short_name}"
  scope                         = azurerm_storage_account.storage_account[each.value.name].id

  storage_queue_endpoint {
    queue_name                  = azurerm_storage_queue.storage_queue_mvr[each.value.name].name
    storage_account_id          = azurerm_storage_account.storage_account[each.value.name].id
    queue_message_time_to_live_in_seconds = 3600
  }

  included_event_types          = ["Microsoft.Storage.BlobCreated", "Microsoft.Storage.BlobDeleted"]
  event_delivery_schema         = "EventGridSchema"

  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440
  }

  subject_filter {
    subject_begins_with  = "/blobServices/default/containers/nvs-mvr"
  }

}


# ## create storage account queue for ai_image_selection and ai_image_highlight
# resource "azurerm_storage_queue" "storage_queue_ai_image_selection" {
#   for_each                      = { for r in var.region_settings : r.name => r }
#   name                          = "blob-event-queue-ai-image-selection-${each.value.short_name}"
#   storage_account_name            = azurerm_storage_account.storage_account[each.value.name].name
# }

# resource "azurerm_storage_queue" "storage_queue_ai_image_highlight" {
#   for_each                      = { for r in var.region_settings : r.name => r }
#   name                          = "blob-event-queue-ai-image-highlight-${each.value.short_name}"
#   storage_account_name            = azurerm_storage_account.storage_account[each.value.name].name
# }