###############################################################################
# Mariam Juma Hamis - Virtual Assistant website
#
#   Browser -> CloudFront (OAC) -> private S3 bucket   (static site)
#   Browser -> Lambda Function URL -> DynamoDB          (review form API)
#
# Everything here replaces what was originally clicked together in the console.
###############################################################################

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Must stay in sync with the "${project_name}-site-*" scope of the deploy role in state-bootstrap.
  site_bucket_name = "${var.project_name}-site-${local.account_id}-${var.aws_region}"
  site_origin_id   = "s3-${var.project_name}-site"
  site_dir         = "${path.module}/${var.website_dir}"

  # file path -> lowercase extension, computed once and reused below
  site_files = {
    for f in fileset(local.site_dir, "**") : f => lower(reverse(split(".", f))[0])
  }

  short_cache_control = "public, max-age=${var.short_cache_max_age_seconds}"
  long_cache_control  = "public, max-age=${var.long_cache_max_age_seconds}"

  lambda_basic_execution_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

  # DynamoDB auto scaling: one target + policy per dimension
  dynamodb_scaling = {
    read = {
      dimension    = "dynamodb:table:ReadCapacityUnits"
      metric       = "DynamoDBReadCapacityUtilization"
      min_capacity = var.dynamodb_read_capacity
    }
    write = {
      dimension    = "dynamodb:table:WriteCapacityUnits"
      metric       = "DynamoDBWriteCapacityUtilization"
      min_capacity = var.dynamodb_write_capacity
    }
  }
}

###############################################################################
# 1. S3 bucket for the website files (private - only CloudFront can read it)
###############################################################################
resource "aws_s3_bucket" "site" {
  bucket = local.site_bucket_name
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.site_noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.site]
}

###############################################################################
# 2. CloudFront: Origin Access Control, clean-URL function, distribution
###############################################################################
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.project_name}-site-oac"
  description                       = "OAC for the ${var.project_name} site bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Rewrites /about -> /about.html and / -> /index.html (see cloudfront/clean-urls.js)
resource "aws_cloudfront_function" "clean_urls" {
  name    = "${var.project_name}-clean-urls"
  runtime = var.cloudfront_function_runtime
  comment = "Clean URLs: /about -> /about.html"
  publish = true
  code    = file("${path.module}/cloudfront/clean-urls.js")
}

data "aws_cloudfront_cache_policy" "site" {
  name = var.cloudfront_cache_policy_name
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = var.cloudfront_http_version
  comment             = "${var.project_name} static website"
  default_root_object = var.index_document
  price_class         = var.cloudfront_price_class

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = local.site_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = local.site_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.site.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.clean_urls.arn
    }
  }

  # With OAC and no s3:ListBucket, S3 answers 403 for missing keys. Show the
  # custom 404 page for both.
  dynamic "custom_error_response" {
    for_each = toset([403, 404])

    content {
      error_code            = custom_error_response.value
      response_code         = 404
      response_page_path    = "/${var.error_document}"
      error_caching_min_ttl = var.cloudfront_error_caching_min_ttl
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.cloudfront_geo_restriction_type
      locations        = var.cloudfront_geo_restriction_type == "none" ? [] : var.cloudfront_geo_restriction_locations
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Allow only this CloudFront distribution to read the bucket.
data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid       = "AllowCloudFrontServicePrincipalReadOnly"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.site]
}

###############################################################################
# 3. Website files (index.html, about.html, error.html, style.css, images/...)
###############################################################################
resource "aws_s3_object" "site_files" {
  for_each = local.site_files

  bucket        = aws_s3_bucket.site.id
  key           = each.key
  source        = "${local.site_dir}/${each.key}"
  etag          = filemd5("${local.site_dir}/${each.key}")
  content_type  = lookup(var.content_types, each.value, var.default_content_type)
  cache_control = contains(var.short_cache_extensions, each.value) ? local.short_cache_control : local.long_cache_control
}

# Tells the page where the review API lives. Generated so the HTML never needs
# editing when the Function URL changes.
resource "aws_s3_object" "config_js" {
  bucket        = aws_s3_bucket.site.id
  key           = "config.js"
  content_type  = var.content_types["js"]
  cache_control = local.short_cache_control
  content       = "window.REVIEW_API_URL = ${jsonencode(aws_lambda_function_url.review_api.function_url)};\n"
}

###############################################################################
# 4. DynamoDB table for reviews
#    Provisioned capacity with auto scaling, AWS-owned key encryption (the
#    default), no secondary indexes.
###############################################################################
resource "aws_dynamodb_table" "reviews" {
  name                        = var.reviews_table_name
  billing_mode                = "PROVISIONED"
  read_capacity               = var.dynamodb_read_capacity
  write_capacity              = var.dynamodb_write_capacity
  hash_key                    = "id"
  deletion_protection_enabled = var.dynamodb_deletion_protection

  attribute {
    name = "id"
    type = "S"
  }

  # Auto scaling changes capacity outside Terraform; don't fight it.
  lifecycle {
    ignore_changes = [read_capacity, write_capacity]
  }
}

resource "aws_appautoscaling_target" "reviews" {
  for_each = local.dynamodb_scaling

  service_namespace  = "dynamodb"
  resource_id        = "table/${aws_dynamodb_table.reviews.name}"
  scalable_dimension = each.value.dimension
  min_capacity       = each.value.min_capacity
  max_capacity       = var.dynamodb_autoscaling_max_capacity
}

resource "aws_appautoscaling_policy" "reviews" {
  for_each = local.dynamodb_scaling

  name               = "${var.reviews_table_name}-${each.key}-scaling"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.reviews[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.reviews[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.reviews[each.key].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value = var.dynamodb_autoscaling_target_utilization

    predefined_metric_specification {
      predefined_metric_type = each.value.metric
    }
  }
}

# Keeps existing state when upgrading from the old per-dimension resources.
moved {
  from = aws_appautoscaling_target.reviews_read
  to   = aws_appautoscaling_target.reviews["read"]
}

moved {
  from = aws_appautoscaling_target.reviews_write
  to   = aws_appautoscaling_target.reviews["write"]
}

moved {
  from = aws_appautoscaling_policy.reviews_read
  to   = aws_appautoscaling_policy.reviews["read"]
}

moved {
  from = aws_appautoscaling_policy.reviews_write
  to   = aws_appautoscaling_policy.reviews["write"]
}

###############################################################################
# 5. Lambda function (review API) + IAM role + logs
###############################################################################
data "archive_file" "review_api" {
  type        = "zip"
  source_file = "${path.module}/${var.lambda_source_file}"
  output_path = "${path.module}/build/${var.lambda_function_name}.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "review_api" {
  name               = "${var.lambda_function_name}-role"
  description        = "Execution role for the ${var.lambda_function_name} Lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# CloudWatch Logs access (the console adds this automatically)
resource "aws_iam_role_policy_attachment" "review_api_logs" {
  role       = aws_iam_role.review_api.name
  policy_arn = local.lambda_basic_execution_policy_arn
}

# Least privilege: only PutItem + Scan, only on the reviews table
data "aws_iam_policy_document" "review_api_dynamodb" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem", "dynamodb:Scan"]
    resources = [aws_dynamodb_table.reviews.arn]
  }
}

resource "aws_iam_role_policy" "review_api_dynamodb" {
  name   = "${var.reviews_table_name}-table-access"
  role   = aws_iam_role.review_api.id
  policy = data.aws_iam_policy_document.review_api_dynamodb.json
}

resource "aws_cloudwatch_log_group" "review_api" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = var.lambda_log_retention_days
}

resource "aws_lambda_function" "review_api" {
  function_name    = var.lambda_function_name
  description      = "Stores and lists reviews for the website"
  role             = aws_iam_role.review_api.arn
  runtime          = var.lambda_runtime
  handler          = var.lambda_handler
  filename         = data.archive_file.review_api.output_path
  source_code_hash = data.archive_file.review_api.output_base64sha256
  timeout          = var.lambda_timeout_seconds
  memory_size      = var.lambda_memory_mb

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.reviews.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.review_api,
    aws_iam_role_policy_attachment.review_api_logs,
    aws_iam_role_policy.review_api_dynamodb,
  ]
}

###############################################################################
# 6. Public Function URL with CORS locked to the CloudFront site
###############################################################################
resource "aws_lambda_function_url" "review_api" {
  function_name      = aws_lambda_function.review_api.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["https://${aws_cloudfront_distribution.site.domain_name}"] # scheme + domain only: no path, no trailing slash
    allow_methods = var.review_api_cors_methods
    allow_headers = var.review_api_cors_headers
    max_age       = var.review_api_cors_max_age_seconds
  }
}

# A NONE-auth Function URL needs BOTH resource-policy statements, otherwise
# callers get 403 AccessDeniedException (the two statements you re-added by
# hand in the console).
resource "aws_lambda_permission" "url_public_access" {
  statement_id           = "FunctionURLAllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.review_api.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "url_invoke_action" {
  statement_id             = "FunctionURLAllowInvokeAction"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.review_api.function_name
  principal                = "*"
  invoked_via_function_url = true
}
