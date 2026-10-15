output "state_bucket_name" {
  description = "Save as the TF_STATE_BUCKET repository variable in GitHub."
  value       = aws_s3_bucket.state.id
}

output "github_actions_role_arn" {
  description = "Save as the AWS_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.github_deploy.arn
}

output "backend_config" {
  description = "Contents for ../backend.hcl (terraform init -backend-config=backend.hcl)."
  value       = <<-EOT
    bucket = "${aws_s3_bucket.state.id}"
    key    = "${var.state_key}"
    region = "${var.aws_region}"
  EOT
}
