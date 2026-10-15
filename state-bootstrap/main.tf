###############################################################################
# One-time bootstrap (run locally with admin credentials, state stays local):
#   - S3 bucket for the main stack's remote state
#   - GitHub OIDC provider + IAM role so GitHub Actions can deploy without keys
###############################################################################
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  state_bucket_name = "${var.project_name}-tfstate-${local.account_id}"
  deploy_role_name  = coalesce(var.deploy_role_name, "${var.project_name}-github-deploy")

  github_oidc_url       = "https://${var.github_oidc_host}"
  github_subject_prefix = coalesce(var.github_subject_prefix, "repo:${var.github_repo}")

  # Pull-request runs (plan), branch runs (plan) and environment runs (apply)
  github_subjects = [
    "${local.github_subject_prefix}:pull_request",
    "${local.github_subject_prefix}:ref:refs/heads/${var.github_branch}",
    "${local.github_subject_prefix}:environment:${var.github_environment}",
  ]
}

# ---------- Remote state bucket ----------
resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket_name

  # Losing this bucket means losing track of every deployed resource.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---------- GitHub OIDC ----------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = local.github_oidc_url
  client_id_list = [var.github_oidc_audience]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = local.github_oidc_url
}

locals {
  oidc_provider_arn = one(concat(
    aws_iam_openid_connect_provider.github[*].arn,
    data.aws_iam_openid_connect_provider.github[*].arn,
  ))
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.github_oidc_host}:aud"
      values   = [var.github_oidc_audience]
    }

    # No wildcards in the subjects, so StringEquals is the tighter operator.
    condition {
      test     = "StringEquals"
      variable = "${var.github_oidc_host}:sub"
      values   = local.github_subjects
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = local.deploy_role_name
  assume_role_policy   = data.aws_iam_policy_document.github_assume.json
  max_session_duration = var.deploy_role_max_session_seconds
}

# Scoped to the services this project uses. Tighten further if you like.
data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "StateBucket"
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }

  # Matches local.site_bucket_name in the main stack.
  statement {
    sid     = "SiteBucket"
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "arn:${local.partition}:s3:::${var.project_name}-site-*",
      "arn:${local.partition}:s3:::${var.project_name}-site-*/*",
    ]
  }

  statement {
    sid       = "ServiceActions"
    effect    = "Allow"
    actions   = var.deploy_service_actions
    resources = ["*"]
  }

  statement {
    sid    = "ProjectRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags", "iam:PassRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:ListRolePolicies", "iam:ListInstanceProfilesForRole", "iam:UpdateAssumeRolePolicy",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/*"]
  }

  statement {
    sid       = "ServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*"]
  }

  statement {
    sid       = "ReadOnlyHelpers"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity", "iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${var.project_name}-deploy-website"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
