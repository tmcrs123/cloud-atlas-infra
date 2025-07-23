locals {
  environment = terraform.workspace
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# variable "sql_admin_user" {
#   description = "SQL admin user"
#   type        = string
#   sensitive   = true
#   default     = "some-user"
# }

variable "callback_url" {
  description = "UI callback url"
  type        = string
  default     = "http://localhost:4200/redirect"
}

locals {
  callback_url = terraform.workspace == "demo" ? "https://demo.cloud-atlas.net/redirect" : terraform.workspace == "prod" ? "https://cloud-atlas.net/redirect" : var.callback_url
}

variable "logout_url" {
  description = "UI logout url"
  type        = string
  default     = "http://localhost:4200"
}

locals {
  logout_url = terraform.workspace == "demo" ? "https://demo.cloud-atlas.net" : terraform.workspace == "prod" ? "https://cloud-atlas.net" : var.logout_url
}

variable "demo_aliases" {
  description = "Aliases for the demo environment"
  type        = list(string)
  default     = ["demo.cloud-atlas.net", "www.demo.cloud-atlas.net"]
}

variable "prod_aliases" {
  description = "Aliases for the demo environment"
  type        = list(string)
  default     = ["cloud-atlas.net", "www.cloud-atlas.net"]
}

locals {
  aliases = terraform.workspace == "demo" ? var.demo_aliases : var.prod_aliases 
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

variable "max_file_size_bytes" {
  description = "UI max filesize in bytes"
  type        = number
  default     = 20971520
}

variable "atlas_limit" {
  description = "atlas limit"
  type        = number
  default     = 25
}

variable "markers_limit" {
  description = "markers limit"
  type        = number
  default     = 25
}

variable "images_limit" {
  description = "images limit"
  type        = number
  default     = 10
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

variable "ui_git_repo" {
  description = "The git repo UI url"
  type        = string
  sensitive   = false
  default     = "https://github.com/tmcrs123/cloud-atlas-ui"
}

variable "ui_git_repo_branch" {
  description = "The branch to use for the UI build"
  type        = string
  default     = "demo"
}

locals {
  ui_git_repo_branch = terraform.workspace == "demo" ? var.ui_git_repo_branch : "master"
}

variable "optimized_photos_cloudfront_public_key_pem" {
  description = "Public key from cloudfront opt dist"
  type        = string
  sensitive   = false
  default     = <<EOF
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArHCqwnfHYWsjydaSnsbk
jjBJQEQl2fFBBNg7q6Ez0y1leV56tot7sIUfc0UNM3OjeZ5ZI3kAUzMiqFatBFmQ
gMEjJ6T2MbmvQifArNtiIyPDjIAReN3cksKRuaNGwVdMNIkN5P0EfnFWiJpY7K8V
M8VEJx7iUVnnZVlPqiEWMLsaLKon5KMB3KRd2I+99itXaRaJBZpO+JXir1lFrTjY
fZBR7qmo6kOfrVopOYOd3NMXmq6bnqYhMSHAI0rxiBrmGcWYkG69SEJXzURuvXB9
TYptXPYL27xRKKxLhR2LBQUxfwYA5/rODsLQ7Z7/ZNPK6cua+269wJBYTH1SMPvf
qwIDAQAB
-----END PUBLIC KEY-----
EOF
}

