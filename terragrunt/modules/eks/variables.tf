variable "eks_cluster_name" {
    description = "The name of the EKS cluster"
    type        = string
}

variable "cluster_version" {
    description = "The Kubernetes version for the EKS cluster"
    type        = string
}

variable "vpc_id" {
    description = "The ID of the VPC"
    type        = string
}

variable "subnet_ids" {
    description = "The IDs of the subnets"
    type        = list(string)
}

variable "vpc_owner_id" {
    description = "The ID of the VPC owner"
    type        = string
}