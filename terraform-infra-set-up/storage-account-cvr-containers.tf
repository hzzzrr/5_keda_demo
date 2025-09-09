# we need to create filesystem instead of container for both cvr and mvr
resource "azurerm_storage_data_lake_gen2_filesystem" "storage_filesystem_cvr5" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "nvs-cvr-5-${each.value.name}"
  storage_account_id            = azurerm_storage_account.storage_account[each.value.name].id
}

resource "azurerm_storage_data_lake_gen2_filesystem" "storage_filesystem_cvr10" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "nvs-cvr-10-${each.value.name}"
  storage_account_id            = azurerm_storage_account.storage_account[each.value.name].id
}


# 创建storage account queue
resource "azurerm_storage_queue" "storage_queue_cvr" {
  for_each                      = { for r in var.region_settings : r.name => r }
  name                          = "blob-event-queue-cvr-${each.value.short_name}"
  storage_account_name            = azurerm_storage_account.storage_account[each.value.name].name
}


# 在每个region创建event grid event subscription，用来触发storage queue
resource "azurerm_eventgrid_event_subscription" "event_subscription_cvr" {
  depends_on                    = [azurerm_storage_queue.storage_queue_cvr]
  for_each                      = { for r in var.region_settings : r.name => r }

  name                          = "storage-event-cvr-${each.value.short_name}"
  scope                         = azurerm_storage_account.storage_account[each.value.name].id

  storage_queue_endpoint {
    queue_name                  = azurerm_storage_queue.storage_queue_cvr[each.value.name].name
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
    subject_begins_with  = "/blobServices/default/containers/nvs-cvr"
  }

}
