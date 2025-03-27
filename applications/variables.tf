# Variables that need to be provided after infrastructure is created
variable "ingest_function_package_url" {
  description = "URL to the packaged ingest function app"
  type        = string
}

variable "ai_function_package_url" {
  description = "URL to the packaged AI function app"
  type        = string
}

variable "adf_sql_connection_string" {
  description = "Connection string for ADF SQL database"
  type        = string
  sensitive   = true
}

variable "ai_sql_connection_string" {
  description = "Connection string for AI SQL database"
  type        = string
  sensitive   = true
}
