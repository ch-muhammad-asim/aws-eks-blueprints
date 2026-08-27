###############################################################################
# EKS - control plane, add-ons and the system managed node group
###############################################################################

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//eks"
}

dependency "vpc" {
  config_path = "../vpc"

  # Mocks let `terragrunt run --all plan` work before the VPC exists.
  mock_outputs = {
    vpc_id          = "vpc-00000000000000000"
    private_subnets = ["subnet-00000000000000000", "subnet-00000000000000001"]
    public_subnets  = ["subnet-00000000000000002", "subnet-00000000000000003"]
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets

  # The sandbox permits t2/t3/t3a/t4g in micro, small and medium only.
  # t3.medium is the largest allowed and the smallest that comfortably holds
  # the system add-ons alongside the Karpenter controller.
  node_instance_types = ["t3.medium", "t3a.medium"]

  # The sandbox caps the account at nine concurrent EC2 instances. Two here
  # leaves room for the nodes Karpenter provisions.
  node_min_size     = 2
  node_max_size     = 3
  node_desired_size = 2
  node_disk_size    = 50

  # Narrow this to your egress CIDR outside a sandbox.
  endpoint_public_access_cidrs = ["0.0.0.0/0"]

  # Control plane logs cost money per GB ingested; enable the ones you will
  # actually read. ["audit", "authenticator"] is the usual production floor.
  enabled_log_types = []

  create_iam_access_roles = true
}
