#  If you don't set the environment variable, it will fall back to using "my-cluster"
# export TF_VAR_eks_cluster_name='cloudgeeks-eks-dev'

include "root" {
  path = find_in_parent_folders()
}

locals {
  eks_cluster_name = get_env("TF_VAR_eks_cluster_name", "my-cluster")
}


terraform {
  source = "../../../../../modules//eks"
}

dependency "vpc" {
  config_path = "../vpc"
}

inputs = {
  cluster_name    = local.eks_cluster_name
  cluster_version = "1.30"
  vpc_id          = dependency.vpc.outputs.vpc.vpc_id
  subnet_ids      = dependency.vpc.outputs.vpc.private_subnets
  vpc_owner_id    = dependency.vpc.outputs.vpc.vpc_owner_id

}