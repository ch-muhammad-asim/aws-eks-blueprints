locals {
  account_name   = "cloudgeeks"
  aws_account_id = "898961940126"

  # Bootstrapped outside Terraform - state storage should not live in the state
  # it stores. See docs/BOOTSTRAP.md for the exact commands.
  state_bucket  = "cloudgeeks-eks-blueprints-tfstate-898961940126"
  state_kms_key = "alias/terraform-state"
}
