# 在每个region中，创建一个resource group，名字中使用region name作为后缀。
resource "azurerm_resource_group" "rg" {
  for_each            = { for r in var.region_settings : r.name => r }
  name                = "${var.rg_name_prefix}-${each.key}"
  location            = each.value.name
}
