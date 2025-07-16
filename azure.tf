# Azure
resource "azurerm_resource_group" "cloud-atlas-resource-group" {
  name     = "cloud-atlas-${local.environment}-resource-group"
  location = "UK South"
}

# sql db
resource "azurerm_mssql_server" "cloud-atlas-sql-server" {
  name                         = "cloud-atlas-${local.environment}-sql-server"
  resource_group_name          = azurerm_resource_group.cloud-atlas-resource-group.name
  location                     = azurerm_resource_group.cloud-atlas-resource-group.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_user
  administrator_login_password = var.sql_admin_password
}

resource "azurerm_mssql_firewall_rule" "cloud-atlas-sql-firewall" {
  name             = "allowAll"
  server_id        = azurerm_mssql_server.cloud-atlas-sql-server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

resource "azurerm_mssql_database" "cloud-atlas-sql-database" {
  name                        = "cloud-atlas-${local.environment}-sql-database"
  server_id                   = azurerm_mssql_server.cloud-atlas-sql-server.id
  sku_name                    = "GP_S_Gen5_1" # General Purpose, Serverless Gen5, 1 vCore max
  max_size_gb                 = 1
  auto_pause_delay_in_minutes = 15  # auto pause after 1/2 hour idle
  min_capacity                = 0.5 # minimum vCore capacity when running
  zone_redundant              = false
}

# cosmosdb
resource "azurerm_cosmosdb_account" "cloud-atlas-cosmosdb" {
  name                = "cloud-atlas-${local.environment}-cosmosdb"
  location            = azurerm_resource_group.cloud-atlas-resource-group.location
  resource_group_name = azurerm_resource_group.cloud-atlas-resource-group.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.cloud-atlas-resource-group.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableServerless"
  }

  automatic_failover_enabled        = false
  multiple_write_locations_enabled  = false
  is_virtual_network_filter_enabled = false
}

resource "azurerm_cosmosdb_sql_database" "cloud-atlas-cosmosdb-db" {
  name                = "cloud-atlas-${local.environment}-db"
  resource_group_name = azurerm_resource_group.cloud-atlas-resource-group.name
  account_name        = azurerm_cosmosdb_account.cloud-atlas-cosmosdb.name
}

resource "azurerm_cosmosdb_sql_container" "cloud-atlas-cosmosdb-container" {
  name                = "cloud-atlas-${local.environment}-container"
  resource_group_name = azurerm_resource_group.cloud-atlas-resource-group.name
  account_name        = azurerm_cosmosdb_account.cloud-atlas-cosmosdb.name
  database_name       = azurerm_cosmosdb_sql_database.cloud-atlas-cosmosdb-db.name
  partition_key_paths = ["/markerId"]

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }
  }
}
