terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.11.0"
    }
  }
}

provider "azurerm" {
  subscription_id = "2ca29aca-e1f9-47af-9f87-1408dbcbec18"
  features {}
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "aidi-data-engineering-rg"
  location = "canadacentral"
}

# Storage Account
resource "azurerm_storage_account" "storage" {
  name                     = "aidistorageacct"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  account_replication_type = "LRS"
}

# Blob Container
resource "azurerm_storage_container" "blob_container" {
  name                  = "aidirawdata"
  storage_account_id    = azurerm_storage_account.storage.id
  container_access_type = "private"
}

# App Service Plan for the Linux Function Apps
resource "azurerm_service_plan" "asp" {
  name                = "aidi-app-service-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "Y1"
}

# Azure SQL Server
resource "azurerm_mssql_server" "sql_server" {
  name                         = "aidisqlserver"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "P@ssw0rd1234!"
}

# SQL Database for Azure Data Factory usage
resource "azurerm_mssql_database" "sql_adf_db" {
  name      = "aidi-adf-db"
  server_id = azurerm_mssql_server.sql_server.id
  timeouts {
    create = "30m"
  }
  depends_on = [azurerm_mssql_server.sql_server]
}

# SQL Database for AI Outputs
resource "azurerm_mssql_database" "sql_ai_db" {
  name      = "aidi-ai-db"
  server_id = azurerm_mssql_server.sql_server.id
  timeouts {
    create = "30m"
  }
  sku_name   = "Basic"
  depends_on = [azurerm_mssql_server.sql_server]
}

# Azure Cognitive Account for Text Analytics
resource "azurerm_cognitive_account" "ai_language" {
  name                = "aidiailanguage"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "TextAnalytics"
  sku_name            = "F0"
}

# Output foundation resource information
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "storage_account_name" {
  value = azurerm_storage_account.storage.name
}

output "storage_account_key" {
  value     = azurerm_storage_account.storage.primary_access_key
  sensitive = true
}

output "storage_connection_string" {
  value     = azurerm_storage_account.storage.primary_connection_string
  sensitive = true
}

output "blob_container_name" {
  value = azurerm_storage_container.blob_container.name
}

output "sql_server_name" {
  value = azurerm_mssql_server.sql_server.name
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.sql_server.fully_qualified_domain_name
}

output "sql_adf_db_name" {
  value = azurerm_mssql_database.sql_adf_db.name
}

output "sql_ai_db_name" {
  value = azurerm_mssql_database.sql_ai_db.name
}

output "ai_language_endpoint" {
  value = azurerm_cognitive_account.ai_language.endpoint
}

output "ai_language_key" {
  value     = azurerm_cognitive_account.ai_language.primary_access_key
  sensitive = true
}

output "app_service_plan_id" {
  value = azurerm_service_plan.asp.id
}
