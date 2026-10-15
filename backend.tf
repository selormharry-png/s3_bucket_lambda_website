# Remote state in S3 with native locking (no DynamoDB lock table needed).
#
# The bucket is created ONCE by ./state-bootstrap (see README.md), because a
# backend cannot create its own bucket. Backend blocks cannot use variables, so
# this is a partial configuration: bucket, key and region are supplied at init.
#
#   Local:  cp backend.hcl.example backend.hcl   # fill in the values
#           terraform init -backend-config=backend.hcl
#   CI:     passed from GitHub repository variables (see the workflow)
terraform {
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
