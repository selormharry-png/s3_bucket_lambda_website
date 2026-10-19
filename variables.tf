###############################################################################
# General
###############################################################################
variable "aws_region" {
  description = "AWS region for all regional resources (S3, Lambda)."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Short name used as a prefix for resource names. Must match project_name in state-bootstrap (the deploy role is scoped to it)."
  type        = string
  default     = "mariam-va"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 chars of lowercase letters, digits and hyphens (it is used in S3 bucket names)."
  }
}

variable "environment" {
  description = "Environment label (used in tags)."
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Owner tag applied to every resource."
  type        = string
  default     = "mariam-juma-hamis"
}

variable "additional_tags" {
  description = "Extra tags merged into the provider default_tags."
  type        = map(string)
  default     = {}
}

###############################################################################
# Website bucket
###############################################################################
variable "website_dir" {
  description = "Local folder (relative to this module) containing the site files uploaded to S3."
  type        = string
  default     = "website"
}

variable "index_document" {
  description = "Object served for / (CloudFront default root object)."
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Object served for missing pages (403/404)."
  type        = string
  default     = "error.html"
}

variable "site_noncurrent_version_retention_days" {
  description = "Days to keep old (noncurrent) versions of site files before they expire."
  type        = number
  default     = 30
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Days after which incomplete multipart uploads to the site bucket are aborted."
  type        = number
  default     = 7
}

variable "content_types" {
  description = "Map of file extension (lowercase, no dot) to Content-Type for uploaded site files."
  type        = map(string)
  default = {
    html = "text/html; charset=utf-8"
    css  = "text/css; charset=utf-8"
    js   = "application/javascript; charset=utf-8"
    json = "application/json"
    txt  = "text/plain; charset=utf-8"
    xml  = "application/xml"
    ico  = "image/x-icon"
    jpg  = "image/jpeg"
    jpeg = "image/jpeg"
    png  = "image/png"
    gif  = "image/gif"
    webp = "image/webp"
    svg  = "image/svg+xml"
  }
}

variable "default_content_type" {
  description = "Content-Type for files whose extension is not in content_types."
  type        = string
  default     = "application/octet-stream"
}

variable "short_cache_extensions" {
  description = "File extensions that get the short browser cache (pages, styles, scripts). Everything else gets the long cache."
  type        = list(string)
  default     = ["html", "css", "js", "json", "txt", "xml"]
}

variable "short_cache_max_age_seconds" {
  description = "Cache-Control max-age for short-cache files and config.js (CI also invalidates CloudFront on deploy)."
  type        = number
  default     = 300
}

variable "long_cache_max_age_seconds" {
  description = "Cache-Control max-age for everything else (images, fonts, ...)."
  type        = number
  default     = 86400
}

###############################################################################
# CloudFront
###############################################################################
variable "cloudfront_price_class" {
  description = "CloudFront price class. PriceClass_100 = North America + Europe (cheapest)."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "cloudfront_http_version" {
  description = "Maximum HTTP version CloudFront supports for viewers."
  type        = string
  default     = "http2and3"
}

variable "cloudfront_cache_policy_name" {
  description = "Name of the managed CloudFront cache policy for the default behaviour."
  type        = string
  default     = "Managed-CachingOptimized"
}

variable "cloudfront_function_runtime" {
  description = "Runtime for the clean-URL CloudFront Function."
  type        = string
  default     = "cloudfront-js-2.0"
}

variable "cloudfront_error_caching_min_ttl" {
  description = "Seconds CloudFront caches 403/404 error responses."
  type        = number
  default     = 60
}

variable "cloudfront_geo_restriction_type" {
  description = "Geo restriction type: none, whitelist or blacklist."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.cloudfront_geo_restriction_type)
    error_message = "cloudfront_geo_restriction_type must be none, whitelist or blacklist."
  }
}

variable "cloudfront_geo_restriction_locations" {
  description = "ISO 3166-1 alpha-2 country codes for the geo restriction (ignored when type is none)."
  type        = list(string)
  default     = []
}

###############################################################################
# Reviews bucket
###############################################################################
variable "reviews_bucket_force_destroy" {
  description = "Allow terraform destroy to delete the reviews bucket even when it still holds reviews. Keep false unless you are tearing the stack down."
  type        = bool
  default     = false
}

variable "reviews_noncurrent_version_retention_days" {
  description = "Days to keep old (noncurrent) versions of review objects, e.g. after a review is moved or deleted."
  type        = number
  default     = 90
}

###############################################################################
# Lambda (review API)
###############################################################################
variable "lambda_function_name" {
  description = "Name of the Lambda function behind the review API."
  type        = string
  default     = "review-api"
}

variable "lambda_source_file" {
  description = "Path (relative to this module) of the Lambda handler source file."
  type        = string
  default     = "lambda/lambda_function.py"
}

variable "lambda_handler" {
  description = "Lambda handler, as <module>.<function>."
  type        = string
  default     = "lambda_function.lambda_handler"
}

variable "lambda_runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.13"
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 10
}

variable "lambda_memory_mb" {
  description = "Lambda memory in MB."
  type        = number
  default     = 128
}

variable "lambda_log_retention_days" {
  description = "CloudWatch Logs retention for the Lambda function."
  type        = number
  default     = 14
}

variable "review_api_cors_methods" {
  description = "HTTP methods the browser may use against the review API Function URL."
  type        = list(string)
  default     = ["GET", "POST"]
}

variable "review_api_cors_headers" {
  description = "Request headers the browser may send to the review API Function URL."
  type        = list(string)
  default     = ["content-type"]
}

variable "review_api_cors_max_age_seconds" {
  description = "Seconds browsers may cache the CORS preflight response."
  type        = number
  default     = 86400
}
