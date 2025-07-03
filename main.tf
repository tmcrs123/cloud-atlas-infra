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
resource "aws_s3_bucket" "ui_bucket" {
  bucket        = "cloud-atlas-${var.environment}-ui"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "ui_bucket_policy" {
  bucket = aws_s3_bucket.ui_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServiceGetObject"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.ui_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket" "lambdas_bucket" {
  bucket        = "cloud-atlas-${var.environment}-lambdas"
  force_destroy = true
}

resource "aws_s3_bucket" "dump_bucket" {
  bucket        = "cloud-atlas-${var.environment}-dump"
  force_destroy = true
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.dump_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process-image-lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process-image-lambda.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.dump_bucket.arn
}

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

data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/../cloud-atlas-lambda/process-image/dist"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "process-image-lambda" {
  function_name    = "cloud-atlas-${var.environment}-process-image"
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  role             = aws_iam_role.lambda-process-image-role.arn

  environment {
    variables = {
      DUMP_BUCKET_NAME = aws_s3_bucket.dump_bucket.bucket,
      OPT_BUCKET_NAME  = aws_s3_bucket.opt_bucket.bucket
    }
  }
}

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

# Cloudfront
resource "aws_cloudfront_origin_access_control" "ui_oac" {
  name                              = "cloud-atlas-${var.environment}-ui-oac"
  description                       = "OAC for UI S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "ui_distribution" {
  enabled = true
  # aliases             = ["demo.cloud-atlas.net", "www.demo.cloud-atlas.net"]
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.ui_bucket.bucket_regional_domain_name
    origin_id                = "cloud-atlas-${var.environment}-ui"
    origin_access_control_id = aws_cloudfront_origin_access_control.ui_oac.id
  }

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = "cloud-atlas-${var.environment}-ui"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf" # CORS-S3Origin
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    error_caching_min_ttl = 10
    response_page_path    = "/index.html"
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    error_caching_min_ttl = 10
    response_page_path    = "/index.html"
  }

  viewer_certificate {
    acm_certificate_arn      = "arn:aws:acm:us-east-1:891376964515:certificate/e0f5ed31-2ed9-41a3-8701-7be09cb4fa18"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "opt_oac" {
  name                              = "cloud-atlas-${var.environment}-opt-oac"
  description                       = "OAC for Optimized S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "opt_distribution" {
  enabled = true

  origin {
    domain_name              = aws_s3_bucket.opt_bucket.bucket_regional_domain_name
    origin_id                = "cloud-atlas-${var.environment}-opt"
    origin_access_control_id = aws_cloudfront_origin_access_control.opt_oac.id
  }

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = "cloud-atlas-${var.environment}-opt"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf" # CORS-S3Origin
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    error_caching_min_ttl = 10
    response_page_path    = "/index.html"
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    error_caching_min_ttl = 10
    response_page_path    = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn      = "arn:aws:acm:us-east-1:891376964515:certificate/e0f5ed31-2ed9-41a3-8701-7be09cb4fa18"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

## UI Code Build
resource "aws_iam_policy" "codebuild_logs_policy" {
  name        = "cloud-atlas-${var.environment}-codebuild-logs-policy"
  description = "Allow CodeBuild to write logs"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "buildPolicyLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "codebuild_ssm_policy" {
  name        = "cloud-atlas-${var.environment}-codebuild-ssm-policy"
  description = "Allow CodeBuild to get SSM parameters"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "buildPolicySSM"
        Effect = "Allow"
        Action = [
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.app_name.arn,
          aws_ssm_parameter.api_endpoint.arn,
          aws_ssm_parameter.authority.arn,
          aws_ssm_parameter.auth_well_known_endpoint_url.arn,
          aws_ssm_parameter.redirect_url.arn,
          aws_ssm_parameter.post_logout_redirect_uri.arn,
          aws_ssm_parameter.clientid.arn,
          aws_ssm_parameter.renew_time_before_token_expires.arn,
          aws_ssm_parameter.region.arn,
          aws_ssm_parameter.user_pool_id.arn,
          aws_ssm_parameter.max_image_file_size_in_bytes.arn,
          aws_ssm_parameter.google_map_id.arn,
          aws_ssm_parameter.google_maps_api_key.arn,
          aws_ssm_parameter.id_token_expiration_in_miliseconds.arn,
          aws_ssm_parameter.logout_uri.arn,
          aws_ssm_parameter.maps_limit.arn,
          aws_ssm_parameter.markers_limit.arn,
          aws_ssm_parameter.images_limit.arn
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "codebuild_s3_policy" {
  name        = "cloud-atlas-${var.environment}-codebuild-s3-policy"
  description = "Allow CodeBuild to access UI S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "buildPolicyS3"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.ui_bucket.arn,
          "${aws_s3_bucket.ui_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "codebuild_codecommit_policy" {
  name        = "cloud-atlas-${var.environment}-codebuild-codecommit-policy"
  description = "Allow CodeBuild to access CodeCommit repository"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "buildPolicyCodeCommit"
        Effect = "Allow"
        Action = [
          "codecommit:GitPull",
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:GetRepository"
        ]
        Resource = "arn:aws:codecommit:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cloud-atlas-ui"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_logs_attach" {
  role       = aws_iam_role.codebuild_service_role.name
  policy_arn = aws_iam_policy.codebuild_logs_policy.arn
}

resource "aws_iam_role_policy_attachment" "codebuild_ssm_attach" {
  role       = aws_iam_role.codebuild_service_role.name
  policy_arn = aws_iam_policy.codebuild_ssm_policy.arn
}

resource "aws_iam_role_policy_attachment" "codebuild_s3_attach" {
  role       = aws_iam_role.codebuild_service_role.name
  policy_arn = aws_iam_policy.codebuild_s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "codebuild_codecommit_attach" {
  role       = aws_iam_role.codebuild_service_role.name
  policy_arn = aws_iam_policy.codebuild_codecommit_policy.arn
}

resource "aws_codebuild_project" "ui_build" {
  name         = "cloud-atlas-ui-build"
  service_role = aws_iam_role.codebuild_service_role.arn

  source {
    type      = "CODECOMMIT"
    location  = "https://git-codecommit.us-east-1.amazonaws.com/v1/repos/cloud-atlas-ui"
    buildspec = "buildspec-ui.yaml"
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "environmentName"
      value = var.environment
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "appName"
      value = aws_ssm_parameter.app_name.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "api_endpoint"
      value = aws_ssm_parameter.api_endpoint.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "authority"
      value = aws_ssm_parameter.authority.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "authWellknownEndpointUrl"
      value = aws_ssm_parameter.auth_well_known_endpoint_url.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "redirectUrl"
      value = aws_ssm_parameter.redirect_url.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "postLogoutRedirectUri"
      value = aws_ssm_parameter.post_logout_redirect_uri.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "clientId"
      value = aws_ssm_parameter.clientid.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "renewTimeBeforeTokenExpiresInSeconds"
      value = aws_ssm_parameter.renew_time_before_token_expires.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "region"
      value = aws_ssm_parameter.region.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "userPoolId"
      value = aws_ssm_parameter.user_pool_id.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "maxImageFileSizeInBytes"
      value = aws_ssm_parameter.max_image_file_size_in_bytes.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "googleMapId"
      value = aws_ssm_parameter.google_map_id.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "googleMapsApiKey"
      value = aws_ssm_parameter.google_maps_api_key.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "idTokenExpirationInMiliseconds"
      value = aws_ssm_parameter.id_token_expiration_in_miliseconds.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "logoutUri"
      value = aws_ssm_parameter.logout_uri.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "mapsLimit"
      value = aws_ssm_parameter.maps_limit.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "markersLimit"
      value = aws_ssm_parameter.markers_limit.value
      type  = "PARAMETER_STORE"
    }

    environment_variable {
      name  = "imagesLimit"
      value = aws_ssm_parameter.images_limit.value
      type  = "PARAMETER_STORE"
    }
  }
}

resource "aws_iam_role" "codebuild_service_role" {
  name = "cloud-atlas-${var.environment}-code-build-service-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:codebuild:${var.aws_region}:${data.aws_caller_identity.current.account_id}:project/cloud-atlas-ui-build"
          }
        }
      }
    ]
  })
}

# SSM Parameters

resource "aws_ssm_parameter" "app_name" {
  name  = "/cloud-atlas/${var.environment}/app-name-parameter"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "api_endpoint" {
  name  = "/cloud-atlas/${var.environment}/api_endpoint"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "authority" {
  name  = "/cloud-atlas/${var.environment}/authority"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "auth_well_known_endpoint_url" {
  name  = "/cloud-atlas/${var.environment}/auth_well_known_endpoint_url"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "redirect_url" {
  name  = "/cloud-atlas/${var.environment}/redirect_url"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "post_logout_redirect_uri" {
  name  = "/cloud-atlas/${var.environment}/post_logout_redirect_uri"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "clientid" {
  name  = "/cloud-atlas/${var.environment}/clientid"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "renew_time_before_token_expires" {
  name  = "/cloud-atlas/${var.environment}/renew_time_before_token_expires"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "region" {
  name  = "/cloud-atlas/${var.environment}/region"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "user_pool_id" {
  name  = "/cloud-atlas/${var.environment}/user_pool_id"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "max_image_file_size_in_bytes" {
  name  = "/cloud-atlas/${var.environment}/max_image_file_size_in_bytes"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "google_map_id" {
  name  = "/cloud-atlas/${var.environment}/google_map_id"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "google_maps_api_key" {
  name  = "/cloud-atlas/${var.environment}/google_maps_api_key"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "id_token_expiration_in_miliseconds" {
  name  = "/cloud-atlas/${var.environment}/id_token_expiration_in_miliseconds"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "logout_uri" {
  name  = "/cloud-atlas/${var.environment}/logout_uri"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "maps_limit" {
  name  = "/cloud-atlas/${var.environment}/maps_limit"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "markers_limit" {
  name  = "/cloud-atlas/${var.environment}/markers_limit"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
}

resource "aws_ssm_parameter" "images_limit" {
  name  = "/cloud-atlas/${var.environment}/images_limit"
  type  = "String"
  value = "cloud-atlas-${var.environment}"
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

  automatic_failover_enabled        = false
  multiple_write_locations_enabled  = false
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
  partition_key_paths = ["/markerId"]

  indexing_policy {
    indexing_mode = "consistent"
  }
}

