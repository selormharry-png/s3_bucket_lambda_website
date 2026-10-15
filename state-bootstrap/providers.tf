provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project   = var.project_name
        ManagedBy = "terraform"
        Stack     = "state-bootstrap"
        Owner     = var.owner
      },
      var.additional_tags,
    )
  }
}
