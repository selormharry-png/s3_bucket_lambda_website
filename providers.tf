terraform {
  # >= 1.10 is required for S3 native state locking (use_lockfile) in backend.tf
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.22+ is needed for aws_lambda_permission.invoked_via_function_url
      version = ">= 6.22.0, < 7.0.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project     = var.project_name
        Environment = var.environment
        ManagedBy   = "terraform"
        Owner       = var.owner
      },
      var.additional_tags,
    )
  }
}
