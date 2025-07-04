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

variable "optimized_photos_cloudfront_public_key_pem" {
  description = "Public key from cloudfront opt dist"
  type        = string
  sensitive   = false
  default     = <<EOF
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA7w6EJyLPRHamMwqC8UsA
/A3lx0A9OaMQmdzPZV9mv8nyEvjpV1pYU0jzD4GlZnu3HwBbFas3l0T1g81EREZ6
FFlCsaklcF3AmgSz/YZJz88f2/LVTdbnHICJPzCvMN+l5CT+wLk/1kqBIgsgTxkc
mmysiVbHpQSXxb+PPBcy8aBjZNMGPhfSs2mdgwsp2PpYXbKkqxXHmXJFlb2h6ESH
cOMVeXX1kKDL13cj5qHSxF4M2CJTFuyXNs6vCMA+2QbJsrLq+SX7NJO0jctRUcQh
+EgnMuJW+ReQu1gJQxLGY3IEqo/e30AQ6Vy3jmah0GhDMXbkVPCYE6RYOTaIvViF
5QIDAQAB
-----END PUBLIC KEY-----
EOF
}

