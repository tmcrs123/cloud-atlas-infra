terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.34.0"
    }
  }
}

provider "azurerm" {
  subscription_id = "164939af-9b80-4554-b1af-1372ab04830e"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

locals {
  process_image_lambda_arn = "arn:aws:lambda:${var.aws_region}:891376964515:function:cloud-atlas-${var.environment}"
}

# API Gateway - missing authorizer
resource "aws_api_gateway_rest_api" "api_gw" {
  name = "cloud-atlas-${var.environment}-api"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "arn:aws:lambda:us-east-1:891376964515:function:cloud-atlas"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gw.execution_arn}/*/*"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api_gw.id
  parent_id   = aws_api_gateway_rest_api.api_gw.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.api_gw.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
  request_parameters = {
    "method.request.path.proxy" = true
  }
  depends_on = [aws_api_gateway_authorizer.cognito_authorizer]
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "cloud-atlas-${var.environment}-cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.api_gw.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.user_pool.arn]
  identity_source = "method.request.header.Authorization"
}

resource "aws_api_gateway_integration" "lambda_proxy" {
  rest_api_id             = aws_api_gateway_rest_api.api_gw.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:891376964515:function:cloud-atlas/invocations"
  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_deployment" "api_gw_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gw.id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_gw_stage" {
  deployment_id = aws_api_gateway_deployment.api_gw_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gw.id
  stage_name    = var.environment
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "cloud-atlas-${var.environment}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  # schema {
  #     name     = "email"
  #     required = true
  #     mutable  = false
  # }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  username_attributes = ["email"]

  mfa_configuration = "OFF"

  email_verification_subject = "Your verification code"
  email_verification_message = "Your verification code is {####}"

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "cloud-atlas-${var.environment}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  supported_identity_providers  = ["COGNITO"]
  generate_secret               = false
  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid"]

  callback_urls = [
    "http://localhost:4200/redirect"
  ]
  logout_urls = [
    "http://localhost:4200"
  ]
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "cloud-atlas-${var.environment}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# S3
resource "aws_s3_bucket" "lambdas_bucket" {
  bucket        = "cloud-atlas-${var.environment}-lambdas"
  force_destroy = true
}

resource "aws_s3_bucket" "dump_bucket" {
  bucket        = "cloud-atlas-${var.environment}-dump"
  force_destroy = true
}

# resource "aws_s3_bucket_notification" "bucket_notification" {
#   bucket = aws_s3_bucket.dump_bucket.id

#   lambda_function {
#     lambda_function_arn = local.process_image_lambda_arn
#     events              = ["s3:ObjectCreated:*"]
#   }
# }

# resource "aws_lambda_permission" "allow_bucket" {
#   statement_id  = "AllowExecutionFromS3Bucket"
#   action        = "lambda:InvokeFunction"
#   function_name = local.process_image_lambda_arn
#   principal     = "s3.amazonaws.com"
#   source_arn    = aws_s3_bucket.dump_bucket.arn
# }

resource "aws_s3_bucket_cors_configuration" "dump_bucket_cors" {
  bucket = aws_s3_bucket.dump_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket" "opt_bucket" {
  bucket        = "cloud-atlas-${var.environment}-opt"
  force_destroy = true
}

resource "aws_s3_bucket_cors_configuration" "opt_bucket_cors" {
  bucket = aws_s3_bucket.opt_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Lambda
# resource "aws_lambda_function" "lambda-api" {
#   function_name = "cloud-atlas-${var.environment}-api"
#   role          = aws_iam_role.lambda-api-role.arn
#   handler       = "index.handler"
#   s3_bucket     = aws_s3_bucket.lambdas_bucket.bucket
#   s3_key        = "change-me"
#   runtime       = "nodejs20.x"
#   memory_size   = 256
#   timeout       = 30

#   environment {
#     variables = {
#       DUMP_BUCKET_NAME = aws_s3_bucket.dump_bucket.bucket,
#       OPT_BUCKET_NAME  = aws_s3_bucket.opt_bucket.bucket
#     }
#   }
# }

resource "aws_iam_role" "lambda-api-role" {
  name = "cloud-atlas-${var.environment}-lambda-api-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role" "lambda-process-image-role" {
  name = "cloud-atlas-${var.environment}-lambda-process-image-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda-api_delete_policy" {
  name        = "cloud-atlas-${var.environment}-lambda-api-s3-delete-policy"
  description = "Allow Cloud Atlas lambda API to delete objects from optimized S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.opt_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_policy" "lambda-process-image-policy" {
  name        = "cloud-atlas-${var.environment}-lambda-process-image-policy"
  description = "Allow Cloud Atlas process image lambda to read and delete from s3 buckets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.dump_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
        ]
        Resource = [
          "${aws_s3_bucket.opt_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_api_role_policy_attach" {
  role       = aws_iam_role.lambda-api-role.name
  policy_arn = aws_iam_policy.lambda-api_delete_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda-process-image-policy_attach" {
  role       = aws_iam_role.lambda-process-image-role.name
  policy_arn = aws_iam_policy.lambda-process-image-policy.arn
}

#SNS topic
resource "aws_sns_topic" "bucket_events_topic" {
  name         = "cloud-atlas-${var.environment}-bucket-events-topic"
  display_name = "cloud-atlas-${var.environment}-bucket-events-topic"
}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic_subscription" "bucket_events_topic_subscription" {
  topic_arn = aws_sns_topic.bucket_events_topic.arn
  protocol  = "lambda"
  endpoint  = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:cloud-atlas-${var.environment}-process-image"
}


# Azure
resource "azurerm_resource_group" "cloud-atlas-resource-group" {
  name     = "cloud-atlas-${var.environment}-resource-group"
  location = "UK South"
}

# sql db
resource "azurerm_mssql_server" "cloud-atlas-sql-server" {
  name                         = "cloud-atlas-${var.environment}-sql-server"
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
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_database" "cloud-atlas-sql-database" {
  name                        = "cloud-atlas-${var.environment}-sql-database"
  server_id                   = azurerm_mssql_server.cloud-atlas-sql-server.id
  sku_name                    = "GP_S_Gen5_1" # General Purpose, Serverless Gen5, 1 vCore max
  max_size_gb                 = 1
  auto_pause_delay_in_minutes = 30  # auto pause after 1/2 hour idle
  min_capacity                = 0.5 # minimum vCore capacity when running
  zone_redundant              = false
}

# cosmosdb
resource "azurerm_cosmosdb_account" "cloud-atlas-cosmosdb" {
    name                = "cloud-atlas-${var.environment}-cosmosdb"
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

    automatic_failover_enabled = false
    multiple_write_locations_enabled = false
    is_virtual_network_filter_enabled = false
}

resource "azurerm_cosmosdb_sql_database" "cloud-atlas-cosmosdb-db" {
    name                = "cloud-atlas-${var.environment}-db"
    resource_group_name = azurerm_resource_group.cloud-atlas-resource-group.name
    account_name        = azurerm_cosmosdb_account.cloud-atlas-cosmosdb.name
}

resource "azurerm_cosmosdb_sql_container" "cloud-atlas-cosmosdb-container" {
    name                = "cloud-atlas-${var.environment}-container"
    resource_group_name = azurerm_resource_group.cloud-atlas-resource-group.name
    account_name        = azurerm_cosmosdb_account.cloud-atlas-cosmosdb.name
    database_name       = azurerm_cosmosdb_sql_database.cloud-atlas-cosmosdb-db.name
    partition_key_paths  = ["/markerId"]

    indexing_policy {
        indexing_mode = "consistent"
    }
}

