terraform {
  backend "s3" {
    bucket       = "s3tfbackend-650251702692-us-east-1-an"
    key          = "url-shortener/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  required_version = ">= 1.10.0"
}

variable "aws_region" {
  type        = string
  description = "The AWS region to deploy into"
  default     = "us-east-1"
}

provider "aws" {
  region = var.aws_region
}

variable "project" {
  type    = string
  default = "serverless-shortener"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ==========================================
# 1. DATABASE (DynamoDB)
# ==========================================
resource "aws_dynamodb_table" "links_table" {
  name         = "${var.project}-links"
  billing_mode = "PAY_PER_REQUEST"

  # Changed from "short_link" to "id" to match your Go struct
  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# ==========================================
# 2. COGNITO (Authentication)
# ==========================================

resource "aws_cognito_user_pool" "pool" {
  name = "${var.project}-user-pool"

  # 1. Allow users to sign themselves up
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  # 2. Tell Cognito to verify emails
  auto_verified_attributes = ["email"]

  # 3. Require email address at sign-up
  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "email"
    required                 = true
  }

  # 4. Configure the automated Verification Email
  verification_message_template {
    # Choose "CONFIRM_WITH_CODE" or "CONFIRM_WITH_LINK"
    default_email_option = "CONFIRM_WITH_CODE"

    email_subject = "Verify your account"
    email_message = "Welcome to our Shortener! Your verification code is {####}."
  }

  # 5. Password Policy (Standard Security Practice)
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project}-auth-${random_string.suffix.result}"
  user_pool_id = aws_cognito_user_pool.pool.id
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.project}-client"
  user_pool_id = aws_cognito_user_pool.pool.id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "phone"]
  supported_identity_providers         = ["COGNITO"]

  # CloudFront domain will be passed dynamically
  callback_urls = ["https://${aws_cloudfront_distribution.frontend.domain_name}"]
  logout_urls   = ["https://${aws_cloudfront_distribution.frontend.domain_name}"]
}

# ==========================================
# 3. LAMBDA & IAM (Backend)
# ==========================================
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "dynamo_access" {
  name = "dynamo_access"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DeleteItem", "dynamodb:UpdateItem"]
      Resource = aws_dynamodb_table.links_table.arn
    }]
  })
}

locals {
  lambda_env_vars = {
    LinkTableName    = aws_dynamodb_table.links_table.name
    DynamoDBEndpoint = ""
    RedisAddress     = "dummy:6379" # Redis ignored intentionally
    RedisPassword    = ""
    RedisDB          = "0"
  }
}

resource "aws_lambda_function" "generate" {
  function_name    = "${var.project}-generate"
  role             = aws_iam_role.lambda_role.arn
  handler          = "bootstrap"
  runtime          = "provided.al2023"
  filename         = "${path.module}/../build/generate.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/generate.zip")
  environment { variables = local.lambda_env_vars }
}

resource "aws_lambda_function" "redirect" {
  function_name    = "${var.project}-redirect"
  role             = aws_iam_role.lambda_role.arn
  handler          = "bootstrap"
  runtime          = "provided.al2023"
  filename         = "${path.module}/../build/redirect.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/redirect.zip")
  environment { variables = local.lambda_env_vars }
}

resource "aws_lambda_function" "delete" {
  function_name    = "${var.project}-delete"
  role             = aws_iam_role.lambda_role.arn
  handler          = "bootstrap"
  runtime          = "provided.al2023"
  filename         = "${path.module}/../build/delete.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/delete.zip")
  environment { variables = local.lambda_env_vars }
}

# ==========================================
# 4. API GATEWAY (With 3 Req/Sec Limit)
# ==========================================
resource "aws_apigatewayv2_api" "api" {
  name          = "${var.project}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://${aws_cloudfront_distribution.frontend.domain_name}"]
    allow_methods = ["*"]
    allow_headers = ["*"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  # Native Throttling: Restricts the API to 3 requests per second
  default_route_settings {
    throttling_rate_limit  = 3
    throttling_burst_limit = 3
  }
}

# Routes & Integrations
locals {
  routes = {
    "PUT /generate" = aws_lambda_function.generate.invoke_arn
    "GET /{id}"     = aws_lambda_function.redirect.invoke_arn
    "DELETE /{id}"  = aws_lambda_function.delete.invoke_arn
  }
}

resource "aws_apigatewayv2_integration" "integrations" {
  for_each         = local.routes
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = each.value

  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "routes" {
  for_each  = local.routes
  api_id    = aws_apigatewayv2_api.api.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.integrations[each.key].id}"
}

resource "aws_lambda_permission" "api_gw" {
  for_each      = { generate = aws_lambda_function.generate.function_name, redirect = aws_lambda_function.redirect.function_name, delete = aws_lambda_function.delete.function_name }
  action        = "lambda:InvokeFunction"
  function_name = each.value
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# ==========================================
# 5. S3 & CLOUDFRONT (Frontend Hosting)
# ==========================================
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.project}-ui-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.frontend.id
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.frontend.id
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  # Expanded restrictions block
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Expanded viewer_certificate block
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn } }
    }]
  })
}

# ==========================================
# 6. UPLOAD FRONTEND FILES DYNAMICALLY
# ==========================================
resource "aws_s3_object" "html" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "../frontend/ServerlessShortener/index.html"
  content_type = "text/html"
  etag         = filemd5("../frontend/ServerlessShortener/index.html")
}

resource "aws_s3_object" "css" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "styles.css"
  source       = "../frontend/ServerlessShortener/styles.css"
  content_type = "text/css"
  etag         = filemd5("../frontend/ServerlessShortener/styles.css")
}

# This generates app.js dynamically injecting API and Cognito info!
resource "aws_s3_object" "app_js" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "app.js"
  content_type = "application/javascript"

  content = templatefile("${path.module}/templates/app.js.tftpl", {
    api_endpoint   = aws_apigatewayv2_api.api.api_endpoint
    cognito_domain = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
    client_id      = aws_cognito_user_pool_client.client.id
    redirect_uri   = "https://${aws_cloudfront_distribution.frontend.domain_name}"
  })
}

output "App_URL" { value = "https://${aws_cloudfront_distribution.frontend.domain_name}" }