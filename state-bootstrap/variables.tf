###############################################################################
# General
###############################################################################
variable "aws_region" {
  description = "Region for the state bucket. Use the same region as the main stack."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Must match project_name in the main stack (used to name the state bucket and scope the deploy role)."
  type        = string
  default     = "mariam-va"
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
# Remote state
###############################################################################
variable "state_key" {
  description = "Object key of the main stack's state file inside the state bucket (printed in the backend_config output)."
  type        = string
  default     = "website/terraform.tfstate"
}

###############################################################################
# GitHub Actions OIDC
###############################################################################
variable "github_repo" {
  description = "GitHub repository allowed to deploy, as owner/repo."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must be in the form owner/repo."
  }
}

variable "github_subject_prefix" {
  description = <<-EOT
    Prefix of the OIDC "sub" claim GitHub sends for this repo. Defaults to repo:<github_repo>.
    Repos using immutable subject claims need repo:<owner>@<owner_id>/<repo>@<repo_id>; get it with:
      gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
  EOT
  type        = string
  default     = null
}

variable "github_branch" {
  description = "Branch whose push runs may plan against the real state."
  type        = string
  default     = "main"
}

variable "github_environment" {
  description = "GitHub environment used by the apply job (add a required reviewer to it for manual approval)."
  type        = string
  default     = "production"
}

variable "create_github_oidc_provider" {
  description = "Set to false if your account already has the GitHub Actions OIDC provider."
  type        = bool
  default     = true
}

variable "github_oidc_host" {
  description = "Host name of the GitHub Actions OIDC token issuer."
  type        = string
  default     = "token.actions.githubusercontent.com"
}

variable "github_oidc_audience" {
  description = "Audience (client ID) GitHub requests in its OIDC token for AWS."
  type        = string
  default     = "sts.amazonaws.com"
}

variable "deploy_role_name" {
  description = "Name of the IAM role GitHub Actions assumes. Defaults to <project_name>-github-deploy."
  type        = string
  default     = null
}

variable "deploy_role_max_session_seconds" {
  description = "Maximum session duration for the deploy role."
  type        = number
  default     = 3600
}

variable "deploy_service_actions" {
  description = "Service-wide actions the deploy role needs to manage the main stack's resources."
  type        = list(string)
  default = [
    "cloudfront:*",
    "lambda:*",
    "logs:*",
  ]
}
