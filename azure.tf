# Azure
resource "azurerm_resource_group" "cloud-atlas-resource-group" {
  name     = "cloud-atlas-${local.environment}-resource-group"
  location = "UK South"
}

# sql db - This creates a PAID table. Currently there's no away to get the free table via terraform


# resource "azurerm_mssql_server" "cloud-atlas-sql-server" {
#   name                         = "cloud-atlas-${local.environment}-sql-server"
#   resource_group_name          = azurerm_resource_group.cloud-atlas-resource-group.name
#   location                     = azurerm_resource_group.cloud-atlas-resource-group.location
#   version                      = "12.0"
#   administrator_login          = var.sql_admin_user
#   administrator_login_password = var.sql_admin_password
# }

# resource "azurerm_mssql_firewall_rule" "cloud-atlas-sql-firewall" {
#   name             = "allowAll"
#   server_id        = azurerm_mssql_server.cloud-atlas-sql-server.id
#   start_ip_address = "0.0.0.0"
#   end_ip_address   = "255.255.255.255"
# }

# resource "azurerm_mssql_database" "cloud-atlas-sql-database" {
#   name                        = "cloud-atlas-${local.environment}-sql-database"
#   server_id                   = azurerm_mssql_server.cloud-atlas-sql-server.id
#   sku_name                    = "GP_S_Gen5_1" # General Purpose, Serverless Gen5, 1 vCore max
#   max_size_gb                 = 1
#   auto_pause_delay_in_minutes = 15  # auto pause after 1/2 hour idle
#   min_capacity                = 0.5 # minimum vCore capacity when running
#   zone_redundant              = false
# }
