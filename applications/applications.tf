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

# Data blocks to reference existing resources created by infrastructure.tf
data "azurerm_resource_group" "rg" {
  name = "aidi-data-engineering-rg"
}

data "azurerm_storage_account" "storage" {
  name                = "aidistorageacct"
  resource_group_name = data.azurerm_resource_group.rg.name
}

data "azurerm_storage_container" "blob_container" {
  name                 = "aidirawdata"
  storage_account_name = data.azurerm_storage_account.storage.name
}

data "azurerm_mssql_server" "sql_server" {
  name                = "aidisqlserver"
  resource_group_name = data.azurerm_resource_group.rg.name
}

data "azurerm_cognitive_account" "ai_language" {
  name                = "aidiailanguage"
  resource_group_name = data.azurerm_resource_group.rg.name
}

data "azurerm_service_plan" "asp" {
  name                = "aidi-app-service-plan"
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Function App 1: Extract reviews from booking.com
resource "azurerm_linux_function_app" "function_ingest" {
  name                       = "aidi-data-ingest-function"
  location                   = data.azurerm_resource_group.rg.location
  resource_group_name        = data.azurerm_resource_group.rg.name
  service_plan_id            = data.azurerm_service_plan.asp.id
  storage_account_name       = data.azurerm_storage_account.storage.name
  storage_account_access_key = data.azurerm_storage_account.storage.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.9"
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = "python"
    WEBSITE_RUN_FROM_PACKAGE = var.ingest_function_package_url
    BLOB_CONTAINER_NAME      = data.azurerm_storage_container.blob_container.name
    AzureWebJobsStorage      = data.azurerm_storage_account.storage.primary_connection_string
  }
}

# Role Assignment: Grant the FunctionApp1 access to Storage Blob Data
resource "azurerm_role_assignment" "function_ingest_blob_access" {
  scope                = data.azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.function_ingest.identity[0].principal_id
}

# Azure Data Factory
resource "azurerm_data_factory" "adf" {
  name                = "aididatafactory"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  identity {
    type = "SystemAssigned"
  }
}

# Role Assignment: Grant ADF Contributor role on the SQL Server for Data Factory
resource "azurerm_role_assignment" "adf_sql_access" {
  scope                = data.azurerm_mssql_server.sql_server.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_data_factory.adf.identity[0].principal_id
}

# Function App 2: Create sentiment analysis using Azure Language Service
resource "azurerm_linux_function_app" "function_ai" {
  name                       = "aidi-ai-processing-function"
  location                   = data.azurerm_resource_group.rg.location
  resource_group_name        = data.azurerm_resource_group.rg.name
  service_plan_id            = data.azurerm_service_plan.asp.id
  storage_account_name       = data.azurerm_storage_account.storage.name
  storage_account_access_key = data.azurerm_storage_account.storage.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.9"
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = "python"
    WEBSITE_RUN_FROM_PACKAGE = var.ai_function_package_url
    ADF_SQL_CONN_STRING      = var.adf_sql_connection_string
    AI_SQL_CONN_STRING       = var.ai_sql_connection_string
    AI_ENDPOINT              = data.azurerm_cognitive_account.ai_language.endpoint
    AI_KEY                   = data.azurerm_cognitive_account.ai_language.primary_access_key
    AzureWebJobsStorage      = data.azurerm_storage_account.storage.primary_connection_string
  }
}

# Role Assignment: Grant SQL DB Contributor role on the SQL Server for the FunctionApp2
resource "azurerm_role_assignment" "function_ai_sql_access" {
  scope                = data.azurerm_mssql_server.sql_server.id
  role_definition_name = "SQL DB Contributor"
  principal_id         = azurerm_linux_function_app.function_ai.identity[0].principal_id
}

# Azure Managed Grafana for Data Visualization
resource "azurerm_dashboard_grafana" "grafana" {
  name                  = "aidi-grafana-dashboard"
  resource_group_name   = data.azurerm_resource_group.rg.name
  location              = data.azurerm_resource_group.rg.location
  grafana_major_version = "10"
  sku                   = "Standard"

  identity {
    type = "SystemAssigned"
  }
}

# Outputs
output "function_ingest_name" {
  value = azurerm_linux_function_app.function_ingest.name
}

output "function_ai_name" {
  value = azurerm_linux_function_app.function_ai.name
}

output "data_factory_name" {
  value = azurerm_data_factory.adf.name
}

output "grafana_url" {
  value = azurerm_dashboard_grafana.grafana.endpoint
}
