include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../../modules//vpc"
}

inputs = {
  vpc_cidr         = "10.60.0.0/16"
  azs              = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets  = ["10.60.0.0/23", "10.60.2.0/23", "10.60.4.0/23"]
  public_subnets   = ["10.60.100.0/23", "10.60.102.0/24", "10.60.104.0/24"]
  database_subnets = ["10.60.11.0/24", "10.60.12.0/24", "10.60.13.0/24"]
  vpc_name         = "my-vpc"
  eks_cluster_name = "my-cluster"
  database_subnet_group_name = "my-database-subnet-group"
}