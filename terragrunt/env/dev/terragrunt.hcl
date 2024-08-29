locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name   = local.account_vars.locals.account_name
  aws_account_id = local.account_vars.locals.aws_account_id
  aws_region     = local.region_vars.locals.aws_region
}

remote_state {
  backend = "s3"
  config = {
    encrypt        = true
    bucket         = "${local.account_name}-terraform-state"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = "terraform-locks"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
)