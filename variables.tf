variable "environment" {
  description = "Name of the environment"
  type        = string
  default     = "stage"
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

variable "sql_admin_password" {
  description = "Password for the SQL admin user"
  type        = string
  sensitive   = true
  default     = "some-password"
}