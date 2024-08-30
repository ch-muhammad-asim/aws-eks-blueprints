variable "vpc_name" {
    description = "The name of the EKS cluster"
    type        = string
}

variable "vpc_cidr" {
    description = "The CIDR block for the VPC"
    type        = string
}

variable "azs" {
    description = "A list of availability zones"
    type        = list(string)
}

variable "private_subnets" {
    description = "A list of private subnets"
    type        = list(string)
}

variable "public_subnets" {
    description = "A list of public subnets"
    type        = list(string)
}

variable "database_subnets" {
    description = "A list of database subnets"
    type        = list(string)
}

variable "database_subnet_group_name" {
    description = "The name of the database subnet group"
    type        = string
}

variable "eks_cluster_name" {
    description = "The name of the EKS cluster"
    type        = string
    default     = "my-cluster" # Add a default value here
}