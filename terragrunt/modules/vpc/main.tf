locals {
  cluster_name = var.eks_cluster_name
}

#########
# Eks Vpc
#########
# https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest
module "vpc" {
  source  = "registry.terraform.io/terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = var.vpc_name

  cidr             = var.vpc_cidr
  azs              = var.azs
  private_subnets  = var.private_subnets
  public_subnets   = var.public_subnets
  database_subnets = var.database_subnets


  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false

  create_database_subnet_group           = true
  database_subnet_group_name             = var.database_subnet_group_name
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = false
  create_database_nat_gateway_route      = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/
  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}"  = "owned"
    "karpenter.sh/discovery/${local.cluster_name}" = local.cluster_name
    "kubernetes.io/role/internal-elb"              = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

}


