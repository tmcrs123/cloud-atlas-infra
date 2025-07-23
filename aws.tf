resource "aws_api_gateway_rest_api" "api_gw" {
  name = "cloud-atlas-${local.environment}-api"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:cloud-atlas-${local.environment}"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gw.execution_arn}/*/*"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api_gw.id
  parent_id   = aws_api_gateway_rest_api.api_gw.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_options" {
  rest_api_id   = aws_api_gateway_rest_api.api_gw.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "proxy_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gw.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
  passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_api_gateway_integration_response" "proxy_options_response" {
  depends_on = [aws_api_gateway_integration.proxy_options_integration]

  rest_api_id = aws_api_gateway_rest_api.api_gw.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS,PATCH'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
  }

  response_templates = {
    "application/json" = ""
  }
}

resource "aws_api_gateway_method_response" "proxy_options_method_response" {
  rest_api_id = aws_api_gateway_rest_api.api_gw.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
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

resource "aws_api_gateway_resource" "healthcheck" {
  rest_api_id = aws_api_gateway_rest_api.api_gw.id
  parent_id   = aws_api_gateway_rest_api.api_gw.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "healthcheck_sub" {
  rest_api_id = aws_api_gateway_rest_api.api_gw.id
  parent_id   = aws_api_gateway_resource.healthcheck.id
  path_part   = "healthcheck"
}

resource "aws_api_gateway_method" "healthcheck_get" {
  rest_api_id   = aws_api_gateway_rest_api.api_gw.id
  resource_id   = aws_api_gateway_resource.healthcheck_sub.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "healthcheck_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.api_gw.id
  resource_id             = aws_api_gateway_resource.healthcheck_sub.id
  http_method             = aws_api_gateway_method.healthcheck_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:cloud-atlas-${local.environment}/invocations"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "cloud-atlas-${local.environment}-cognito-authorizer"
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
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:cloud-atlas-${local.environment}/invocations"
  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_deployment" "api_gw_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gw.id

  # Force a new deployment when any of these resources change
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy_options.id,
      aws_api_gateway_method.proxy_method.id,
      aws_api_gateway_integration.proxy_options_integration.id,
      aws_api_gateway_integration.lambda_proxy.id,
      aws_api_gateway_integration_response.proxy_options_response.id,
      aws_api_gateway_method_response.proxy_options_method_response.id,
      aws_api_gateway_resource.healthcheck.id,
      aws_api_gateway_resource.healthcheck_sub.id,
      aws_api_gateway_method.healthcheck_get.id,
      aws_api_gateway_integration.healthcheck_lambda.id,
      aws_api_gateway_authorizer.cognito_authorizer.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_gw_stage" {
  deployment_id = aws_api_gateway_deployment.api_gw_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gw.id
  stage_name    = local.environment
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "cloud-atlas-${local.environment}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

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
  name         = "cloud-atlas-${local.environment}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  supported_identity_providers  = ["COGNITO"]
  generate_secret               = false
  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"

  access_token_validity  = 60  # 1 hour
  id_token_validity      = 120 # 1 hour
  refresh_token_validity = 30  # 30 days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid"]

  callback_urls = [
    local.callback_url,
  ]
  
  logout_urls = [
    local.logout_url
  ]
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "cloud-atlas-${local.environment}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# S3
resource "aws_s3_bucket" "ui_bucket" {
  bucket        = "cloud-atlas-${local.environment}-ui"
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
            "AWS:SourceArn" = "${aws_cloudfront_distribution.ui_distribution.arn}"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "opt_bucket_policy" {
  bucket = aws_s3_bucket.opt_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "PolicyForCloudFrontPrivateContent"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.opt_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudfront::${var.aws_account_id}:distribution/${aws_cloudfront_distribution.opt_distribution.id}"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket" "lambdas_bucket" {
  bucket        = "cloud-atlas-${local.environment}-lambdas"
  force_destroy = true
}

resource "aws_s3_bucket" "dump_bucket" {
  bucket        = "cloud-atlas-${local.environment}-dump"
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
    allowed_methods = ["PUT"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket" "opt_bucket" {
  bucket        = "cloud-atlas-${local.environment}-opt"
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

resource "aws_dynamodb_table" "photos-table" {
  name         = "cloud-atlas-${local.environment}-photos"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "atlasId"
  range_key    = "markerId"

  attribute {
    name = "atlasId"
    type = "S"
  }

  attribute {
    name = "markerId"
    type = "S"
  }
}

data "archive_file" "process_image_lambda_source" {
  type        = "zip"
  source_file = "${path.module}/../cloud-atlas-lambda/process-image/index.mjs"
  output_path = "${path.module}/../cloud-atlas-lambda/process-image/process-image.zip"
}

resource "aws_lambda_layer_version" "sharp-layer" {
  layer_name               = "cloud-atlas-${local.environment}-sharp-layer"
  filename                 = "${path.module}/../cloud-atlas-lambda/process-image/sharp_layer.zip"
  compatible_runtimes      = ["nodejs20.x", "nodejs22.x"]
  description              = "Dependencies for process-image lambda"
  compatible_architectures = ["arm64"]
}

resource "aws_lambda_function" "process-image-lambda" {
  layers           = [aws_lambda_layer_version.sharp-layer.arn]
  function_name    = "cloud-atlas-${local.environment}-process-image"
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  filename         = data.archive_file.process_image_lambda_source.output_path
  source_code_hash = data.archive_file.process_image_lambda_source.output_base64sha256
  role             = aws_iam_role.lambda-process-image-role.arn
  timeout          = 30
  memory_size      = 1024
  architectures    = ["arm64"]

  environment {
    variables = {
      DUMP_BUCKET_NAME      = aws_s3_bucket.dump_bucket.bucket,
      OPTIMIZED_BUCKET_NAME = aws_s3_bucket.opt_bucket.bucket
    }
  }
}

resource "aws_iam_role" "lambda-api-role" {
  name = "cloud-atlas-${local.environment}-lambda-api-role"
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
  name = "cloud-atlas-${local.environment}-lambda-process-image-role"
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

resource "aws_iam_policy" "lambda-api-policy" {
  name        = "cloud-atlas-${local.environment}-lambda-api-policy"
  description = "Cloud Atlas lambda API permissions"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:Delete",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = [
          aws_dynamodb_table.photos-table.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = [
          "${aws_s3_bucket.opt_bucket.arn}",
        ]
      },
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
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.dump_bucket.arn}/*"
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
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "${aws_secretsmanager_secret.cloudfront_private_key.arn}"
      }
    ]
  })
}

resource "aws_iam_policy" "lambda-process-image-policy" {
  name        = "cloud-atlas-${local.environment}-lambda-process-image-policy"
  description = "Allow Cloud Atlas process image lambda to read and delete from s3 buckets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = [
          "${aws_s3_bucket.dump_bucket.arn}",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = [
          "${aws_s3_bucket.opt_bucket.arn}",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
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
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.photos-table.arn
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
  policy_arn = aws_iam_policy.lambda-api-policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda-process-image-policy_attach" {
  role       = aws_iam_role.lambda-process-image-role.name
  policy_arn = aws_iam_policy.lambda-process-image-policy.arn
}

#SNS topic
resource "aws_sns_topic" "bucket_events_topic" {
  name         = "cloud-atlas-${local.environment}-bucket-events-topic"
  display_name = "cloud-atlas-${local.environment}-bucket-events-topic"
}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic_subscription" "bucket_events_topic_subscription" {
  topic_arn = aws_sns_topic.bucket_events_topic.arn
  protocol  = "lambda"
  endpoint  = "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:cloud-atlas-${local.environment}-process-image"
}

# Cloudfront
resource "aws_cloudfront_origin_access_control" "ui_oac" {
  name                              = "cloud-atlas-${local.environment}-ui-oac"
  description                       = "OAC for UI S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "ui_distribution" {
  enabled             = true
  aliases             = local.aliases
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.ui_bucket.bucket_regional_domain_name
    origin_id                = "cloud-atlas-${local.environment}-ui"
    origin_access_control_id = aws_cloudfront_origin_access_control.ui_oac.id
  }

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = "cloud-atlas-${local.environment}-ui"
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
    acm_certificate_arn      = "arn:aws:acm:${var.aws_region}:${var.aws_account_id}:certificate/e0f5ed31-2ed9-41a3-8701-7be09cb4fa18"
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
  name                              = "cloud-atlas-${local.environment}-opt-oac"
  description                       = "OAC for Optimized S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "opt_distribution" {
  enabled = true

  origin {
    domain_name              = aws_s3_bucket.opt_bucket.bucket_regional_domain_name
    origin_id                = "cloud-atlas-${local.environment}-opt"
    origin_access_control_id = aws_cloudfront_origin_access_control.opt_oac.id
  }

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = "cloud-atlas-${local.environment}-opt"
    trusted_key_groups       = [aws_cloudfront_key_group.optimized_photos_key_group.id]
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
    acm_certificate_arn      = "arn:aws:acm:${var.aws_region}:${var.aws_account_id}:certificate/e0f5ed31-2ed9-41a3-8701-7be09cb4fa18"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_cloudfront_key_group" "optimized_photos_key_group" {
  name = "cloud-atlas-${local.environment}-optimized-photos-cloudfront-keygroup"
  items = [
    aws_cloudfront_public_key.optimized_photos_public_key.id
  ]
}

resource "aws_cloudfront_public_key" "optimized_photos_public_key" {
  name        = "cloud-atlas-${local.environment}-optimized-photos-cloudfront-public-key"
  comment     = "Public key for optimized photos CloudFront distribution"
  encoded_key = var.optimized_photos_cloudfront_public_key_pem

  lifecycle {
    ignore_changes = [encoded_key]
  }
}

resource "random_string" "cloudfront_secret_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "aws_secretsmanager_secret" "cloudfront_private_key" {
  name        = "cloud-atlas-${local.environment}-cloudfront-private-key-${random_string.cloudfront_secret_suffix.result}"
  description = "The private key used by cloudfront to sign urls"
}

resource "aws_secretsmanager_secret_version" "cloudfront_private_key_version" {
  secret_id     = aws_secretsmanager_secret.cloudfront_private_key.id
  secret_string = file("./keys/private_${local.environment}_key.pem")
}

## UI Code Build
resource "aws_iam_policy" "codebuild_logs_policy" {
  name        = "cloud-atlas-${local.environment}-codebuild-logs-policy"
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
  name        = "cloud-atlas-${local.environment}-codebuild-ssm-policy"
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
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "codebuild_s3_policy" {
  name        = "cloud-atlas-${local.environment}-codebuild-s3-policy"
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
  name        = "cloud-atlas-${local.environment}-codebuild-codecommit-policy"
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
        Resource = "arn:aws:codecommit:${var.aws_region}:${var.aws_account_id}:cloud-atlas-ui"
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
    type            = "GITHUB"
    location        = var.ui_git_repo
    git_clone_depth = 1
    buildspec       = "buildspec-ui.yaml"
  }

  source_version = local.ui_git_repo_branch

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "environment"
      value = local.environment
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "app_name"
      value = aws_ssm_parameter.app_name.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "api_endpoint"
      value = "${aws_ssm_parameter.api_endpoint.value}/api"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "authority"
      value = aws_ssm_parameter.authority.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "auth_well_known_endpoint_url"
      value = aws_ssm_parameter.auth_well_known_endpoint_url.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "redirect_url"
      value = aws_ssm_parameter.redirect_url.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "post_logout_redirect_uri"
      value = aws_ssm_parameter.post_logout_redirect_uri.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "client_id"
      value = aws_ssm_parameter.clientid.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "renew_time_before_token_expires"
      value = aws_ssm_parameter.renew_time_before_token_expires.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "region"
      value = aws_ssm_parameter.region.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "user_pool_id"
      value = aws_ssm_parameter.user_pool_id.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "max_image_file_size_in_bytes"
      value = aws_ssm_parameter.max_image_file_size_in_bytes.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "google_map_id"
      value = aws_ssm_parameter.google_map_id.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "google_maps_api_key"
      value = aws_ssm_parameter.google_maps_api_key.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "id_token_expiration_in_miliseconds"
      value = aws_ssm_parameter.id_token_expiration_in_miliseconds.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "logout_uri"
      value = aws_ssm_parameter.logout_uri.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "maps_limit"
      value = aws_ssm_parameter.atlas_limit.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "markers_limit"
      value = aws_ssm_parameter.markers_limit.value
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "images_limit"
      value = aws_ssm_parameter.images_limit.value
      type  = "PLAINTEXT"
    }
  }
}

resource "aws_iam_role" "codebuild_service_role" {
  name = "cloud-atlas-${local.environment}-code-build-service-role"
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
            "aws:SourceArn" = "arn:aws:codebuild:${var.aws_region}:${var.aws_account_id}:project/cloud-atlas-ui-build"
          }
        }
      }
    ]
  })
}

# SSM Parameters

resource "aws_ssm_parameter" "app_name" {
  name  = "cloud-atlas_${local.environment}_app_name"
  type  = "String"
  value = "cloud-atlas-${local.environment}"
}

resource "aws_ssm_parameter" "environment" {
  name  = "cloud-atlas_${local.environment}_environment"
  type  = "String"
  value = local.environment
}

resource "aws_ssm_parameter" "api_endpoint" {
  name  = "cloud-atlas_${local.environment}_api_endpoint"
  type  = "String"
  value = aws_api_gateway_stage.api_gw_stage.invoke_url
}

resource "aws_ssm_parameter" "authority" {
  name  = "cloud-atlas_${local.environment}_authority"
  type  = "String"
  value = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.user_pool.id}"
}

resource "aws_ssm_parameter" "auth_well_known_endpoint_url" {
  name  = "cloud-atlas_${local.environment}_auth_well_known_endpoint_url"
  type  = "String"
  value = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.user_pool.id}"
}

resource "aws_ssm_parameter" "redirect_url" {
  name  = "cloud-atlas_${local.environment}_redirect_url"
  type  = "String"
  value = local.callback_url
}

resource "aws_ssm_parameter" "post_logout_redirect_uri" {
  name  = "cloud-atlas_${local.environment}_post_logout_redirect_uri"
  type  = "String"
  value = local.logout_url
}

resource "aws_ssm_parameter" "clientid" {
  name  = "cloud-atlas_${local.environment}_client_id"
  type  = "String"
  value = aws_cognito_user_pool_client.user_pool_client.id
}

resource "aws_ssm_parameter" "renew_time_before_token_expires" {
  name  = "cloud-atlas_${local.environment}_renew_time_before_token_expires"
  type  = "String"
  value = var.token_renew_time
}

resource "aws_ssm_parameter" "region" {
  name  = "cloud-atlas_${local.environment}_region"
  type  = "String"
  value = var.aws_region
}

resource "aws_ssm_parameter" "user_pool_id" {
  name  = "cloud-atlas_${local.environment}_user_pool_id"
  type  = "String"
  value = aws_cognito_user_pool.user_pool.id
}

resource "aws_ssm_parameter" "max_image_file_size_in_bytes" {
  name  = "cloud-atlas_${local.environment}_max_image_file_size_in_bytes"
  type  = "String"
  value = var.max_file_size_bytes
}

resource "aws_ssm_parameter" "google_map_id" {
  name  = "cloud-atlas_${local.environment}_google_map_id"
  type  = "String"
  value = var.google_map_id
}

resource "aws_ssm_parameter" "google_maps_api_key" {
  name  = "cloud-atlas_${local.environment}_google_maps_api_key"
  type  = "String"
  value = var.google_map_key
}

resource "aws_ssm_parameter" "id_token_expiration_in_miliseconds" {
  name  = "cloud-atlas_${local.environment}_id_token_expiration_in_miliseconds"
  type  = "String"
  value = var.token_expiration_time
}

resource "aws_ssm_parameter" "logout_uri" {
  name  = "cloud-atlas_${local.environment}_logout_uri"
  type  = "String"
  value = local.logout_url
}

resource "aws_ssm_parameter" "atlas_limit" {
  name  = "cloud-atlas_${local.environment}_atlas_limit"
  type  = "String"
  value = var.atlas_limit
}

resource "aws_ssm_parameter" "markers_limit" {
  name  = "cloud-atlas_${local.environment}_markers_limit"
  type  = "String"
  value = var.markers_limit
}

resource "aws_ssm_parameter" "images_limit" {
  name  = "cloud-atlas_${local.environment}_images_limit"
  type  = "String"
  value = var.images_limit
}
