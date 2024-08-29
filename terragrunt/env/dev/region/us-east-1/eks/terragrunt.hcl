include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../../modules//eks"
}

dependency "vpc" {
  config_path = "../vpc"
}

inputs = {
  cluster_name    = "my-cluster" # Must be same as mentioned in vpc module because karpenter tags are based on this name
  cluster_version = "1.30"
  vpc_id          = dependency.vpc.outputs.vpc.vpc_id
  subnet_ids      = dependency.vpc.outputs.vpc.private_subnets
  vpc_owner_id    = dependency.vpc.outputs.vpc.vpc_owner_id

}