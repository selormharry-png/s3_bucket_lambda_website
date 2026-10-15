output "website_url" {
  description = "Public URL of the website."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (used for cache invalidation in CI)."
  value       = aws_cloudfront_distribution.site.id
}

output "site_bucket_name" {
  description = "S3 bucket that holds the website files."
  value       = aws_s3_bucket.site.id
}

output "review_api_url" {
  description = "Lambda Function URL used by the review form (also written to /config.js)."
  value       = aws_lambda_function_url.review_api.function_url
}

output "reviews_table_name" {
  description = "DynamoDB table holding reviews. Set approved=true (Boolean) on an item to publish it."
  value       = aws_dynamodb_table.reviews.name
}

output "aws_region" {
  description = "Region everything was deployed to."
  value       = var.aws_region
}
