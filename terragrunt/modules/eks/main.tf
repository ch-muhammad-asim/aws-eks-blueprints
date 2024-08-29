########################################################
# Must Install the latest version of aws cli & terraform
########################################################
# https://karpenter.sh/v0.23.0/getting-started/getting-started-with-terraform/

#############
# Eks Cluster
#############
# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest

module "eks" {
  source  = "registry.terraform.io/terraform-aws-modules/eks/aws"
  version = "19.16.0"

  cluster_name                    = var.cluster_name
  cluster_version                 = var.cluster_version
  vpc_id                          = var.vpc_id
  subnet_ids                      = var.subnet_ids
  enable_irsa                     = true
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true


  cluster_addons = {
    coredns = {
      resolve_conflicts_on_update = "OVERWRITE"
    }
    kube-proxy = {}
    vpc-cni = {
      resolve_conflicts_on_update = "OVERWRITE"
    }
    aws-ebs-csi-driver = {
      resolve_conflicts_on_update = "OVERWRITE"
    }
  }

  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "Egress Allowed 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
    ingress_nodes_karpenter_ports_tcp = {
      description                = "Karpenter required port"
      protocol                   = "tcp"
      from_port                  = 8443
      to_port                    = 8443
      type                       = "ingress"
      source_node_security_group = true
    }
    # Note: This is not required for Istio
    ##################################################################################
    # Allow All Traffic from Managed Node Security Group to Eks Cluster Security Group
    ###################################################################################
    ingress_nodes_all = {
      description = "Ingress Allowed All from EKS Cluster Security Group"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      #source_cluster_security_group = true
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {

    ingress_self_all = {
      description = "Self allow all ingress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }



    egress_all = {
      description      = "Egress allow all"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }

    # Note: This is required for Istio
    ##########################################################################
    # Allow All Traffic from Eks Cluster Security Group to Node Security Group
    ##########################################################################
    ingress_nodes_all = {
      description                   = "Ingress Allowed All from EKS Cluster Security Group"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
      # source_node_security_group = true
    }




    egress_all = {
      description      = "Egress allow all"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }


  }

  # Create, update, and delete timeout configurations for the cluster
  cluster_timeouts = {
    create = "60m"
    delete = "30m"
  }

  create_iam_role = true
  iam_role_name   = "eks-cluster-role"


  cluster_enabled_log_types = []

  create_cluster_security_group       = true
  create_node_security_group          = true
  node_security_group_use_name_prefix = false
  node_security_group_tags = {
    "karpenter.sh/discovery/${var.cluster_name}" = var.cluster_name
  }


  # Sub Module

  # https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest/submodules/eks-managed-node-group

  eks_managed_node_groups = {

    on-demand = {
      min_size     = 3
      max_size     = 3
      desired_size = 3
      update_config = {
        max_unavailable = 1
      }

      iam_role_additional_policies = {
        AmazonEKSVPCResourceController = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
        AmazonSSMManagedInstanceCore   = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
        AmazonEBSCSIDriverPolicy       = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }


      create_launch_template     = true
      instance_types             = ["t3a.medium"]
      capacity_type              = "ON_DEMAND"
      subnet_ids                 = var.subnet_ids
      use_custom_launch_template = true
      enable_monitoring          = true
      ebs_optimized              = true

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      tags = {
        Environment = "dev"
        Terraform   = "true"
      }
      labels = {
        Environment                  = "dev"
        lifecycle                    = "Ec2OnDemand"
        "karpenter.sh/capacity-type" = "on-demand"
      }
    }



    spot = {
      min_size     = 0
      max_size     = 1
      desired_size = 0

      iam_role_additional_policies = {
        AmazonEKSVPCResourceController = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
        AmazonSSMManagedInstanceCore   = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
        AmazonEBSCSIDriverPolicy       = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }


      create_launch_template     = true
      instance_types             = ["t3a.medium"]
      capacity_type              = "SPOT"
      subnet_ids                 = var.subnet_ids
      use_custom_launch_template = true
      disk_type                  = "gp3"
      disk_encrypted             = true
      disk_size                  = 50
      update_config = {
        max_unavailable = 1
      }
      enable_monitoring = true
      ebs_optimized     = true
      labels = {
        Environment                  = "dev"
        lifecycle                    = "Ec2Spot"
        "aws.amazon.com/spot"        = "true"
        "karpenter.sh/capacity-type" = "spot"
      }



      tags = {
        Environment = "dev"
        Terraform   = "true"
      }
    }


  }

  tags = {
    "karpenter.sh/discovery/${var.cluster_name}" = var.cluster_name
  }


  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = module.eks_admins_iam_role.iam_role_arn
      username = module.eks_admins_iam_role.iam_role_name
      groups   = ["system:masters"]
    },
    {
      rolearn  = module.eks_developers_iam_role.iam_role_arn
      username = module.eks_developers_iam_role.iam_role_name
      groups   = ["reader"]
    },

  ]

}

###################
# EKS Admins Group
###################
# Simple IAM Policy creation to allow EKS Admin access # Step 1
module "allow_eks_access_iam_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "5.3.1"

  name          = "allow-eks-access-to-${var.cluster_name}"
  create_policy = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "eks:DescribeCluster",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

# EKS Admin IAM Role                                        # Step 2
module "eks_admins_iam_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "5.3.1"

  role_name         = "eks-admin-${var.cluster_name}"
  create_role       = true
  role_requires_mfa = false

  custom_role_policy_arns = [module.allow_eks_access_iam_policy.arn]

  trusted_role_arns = [
    "arn:aws:iam::${var.vpc_owner_id}:root"
  ]
}


# STS Policy to Assume EKS Admin IAM Role                  # Step 3
module "allow_assume_eks_admins_iam_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "5.3.1"

  name          = "allow-assume-eks-admin-iam-role-for-${var.cluster_name}"
  create_policy = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Effect   = "Allow"
        Resource = module.eks_admins_iam_role.iam_role_arn
      },
    ]
  })
}


# EKS Cluster Access IAM Group creation add users in this eks-admin group from AWS IAM Console
# Create IAM Group & attach STS Policy # Step 4
module "eks_admins_iam_group" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-group-with-policies"
  version = "5.3.1"

  name                              = "eks-admin-${var.cluster_name}"
  attach_iam_self_management_policy = false
  create_group                      = true
  custom_group_policy_arns          = [module.allow_assume_eks_admins_iam_policy.arn]
}

#####################
# EKS Developer Group
#####################
# Simple IAM Policy creation to allow EKS Developer access # Step 1
module "allow_developers_eks_console_access" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "5.3.1"

  name          = "eks-developers-console-access-${var.cluster_name}"
  create_policy = true

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "eks:*"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : "iam:PassRole",
        "Resource" : "*",
        "Condition" : {
          "StringEquals" : {
            "iam:PassedToService" : "eks.amazonaws.com"
          }
        }
      }
    ]
  })
}

# EKS Developers IAM Role                       # Step 2
# https://github.com/terraform-aws-modules/terraform-aws-iam/blob/master/examples/iam-assumable-role/main.tf
data "aws_caller_identity" "current" {}


module "eks_developers_iam_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "5.3.1"

  role_name         = "eks-developers-${var.cluster_name}"
  create_role       = true
  role_requires_mfa = false

  custom_role_policy_arns = [module.allow_developers_eks_console_access.arn]
  # https://github.com/terraform-aws-modules/terraform-aws-iam/blob/master/examples/iam-assumable-role/main.tf

  custom_role_trust_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : "sts:AssumeRole",
        "Principal" : {
          "AWS" : data.aws_caller_identity.current.account_id
        },
        "Condition" : {}
      }
    ]
  })

}





# STS Policy to Assume EKS Admin IAM Role                  # Step 3
module "allow_assume_eks_developers_iam_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "5.3.1"

  name          = "allow-assume-eks-developers-iam-role-for-${var.cluster_name}"
  create_policy = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Effect   = "Allow"
        Resource = module.eks_developers_iam_role.iam_role_arn
      },
    ]
  })
}


# EKS Cluster Access IAM Group creation add users in this eks-developers group from AWS IAM Console
# Create IAM Group & attach STS Policy # Step 4
module "eks_developers_iam_group" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-group-with-policies"
  version = "5.3.1"

  name                              = "eks-developers-${var.cluster_name}"
  attach_iam_self_management_policy = false
  create_group                      = true
  custom_group_policy_arns          = [module.allow_assume_eks_developers_iam_policy.arn]
}

# https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2009
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
  depends_on = [
    module.eks.eks_managed_node_groups,
  ]
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
  depends_on = [
    module.eks.eks_managed_node_groups,
  ]
}

# https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2009

# https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2525

# Kubernetes Provider
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  token                  = data.aws_eks_cluster_auth.this.token
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    # args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", "default"]
  }
}

# Eks Blueprints Addons Module
# https://github.com/aws-ia/terraform-aws-eks-blueprints/tree/main/modules/kubernetes-addons (Note this is removed 404)
# Example https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/main/examples/karpenter/main.tf
# https://github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.25.0
# https://registry.terraform.io/modules/aws-ia/eks-blueprints-addons/aws/latest

# https://github.com/aws-ia/terraform-aws-eks-blueprints/issues/1630
# https://github.com/aws-ia/terraform-aws-eks-blueprints/releases
# Sub Module
module "kubernetes_addons" {
  source                       = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.32.1"
  eks_cluster_id               = module.eks.cluster_name
  eks_cluster_endpoint         = module.eks.cluster_endpoint
  eks_oidc_provider            = module.eks.oidc_provider
  eks_cluster_version          = var.cluster_version
  eks_worker_security_group_id = module.eks.node_security_group_id



  enable_aws_load_balancer_controller = true
  enable_metrics_server               = true
  enable_cluster_autoscaler           = false

  enable_karpenter = true
  karpenter_helm_config = {
    name       = "karpenter"
    chart      = "karpenter"
    repository = "oci://public.ecr.aws/karpenter"
    version    = "v0.30.0"
    namespace  = "karpenter"
  }
}

# https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2525
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    token                  = data.aws_eks_cluster_auth.this.token
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      #args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", "default"]
    }
  }

}
