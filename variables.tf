# variable "environment" {
#   description = "Name of the environment"
#   type        = string
#   default     = "demo"
# }

locals {
  environment = terraform.workspace
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "sql_admin_user" {
  description = "SQL admin user"
  type        = string
  sensitive   = true
  default     = "some-user"
}

variable "callback_url" {
  description = "UI callback url"
  type        = string
  default     = "http://localhost:4200/redirect"
}

variable "logout_url" {
  description = "UI logout url"
  type        = string
  default     = "http://localhost:4200/redirect"
}

variable "token_renew_time" {
  description = "UI token renew time in seconds"
  type        = number
  default     = 3600
}

variable "token_expiration_time" {
  description = "UI token expiration time in milliseconds"
  type        = number
  default     = 86400000
}

variable "max_file_bytes" {
  description = "UI max filesize in bytes"
  type        = number
  default     = 20971520
}

variable "atlas_limit" {
  description = "atlas limit"
  type        = number
  default     = 10
}

variable "markers_limit" {
  description = "markers limit"
  type        = number
  default     = 10
}

variable "photos_limit" {
  description = "photos limit"
  type        = number
  default     = 10
}

variable "sql_admin_password" {
  description = "Password for the SQL admin user"
  type        = string
  sensitive   = true
  default     = "some-password"
}

variable "azure_subscription_id" {
  description = "Azure subscription Id"
  type        = string
  sensitive   = true
  default     = "some id"
}

variable "aws_account_id" {
  description = "AWS account Id"
  type        = string
  sensitive   = true
  default     = "some id"
}

variable "google_map_id" {
  description = "Google map Id"
  type        = string
  sensitive   = true
  default     = "some id"
}

variable "google_map_key" {
  description = "Google map key"
  type        = string
  sensitive   = true
  default     = "some id"
}