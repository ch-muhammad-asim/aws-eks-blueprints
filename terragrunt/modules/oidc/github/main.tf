locals {
  github_repos = var.github_repos
}

module "github_oidc" {
  source  = "unfunco/oidc-github/aws"
  version = "1.8.0"

  github_repositories = local.github_repos

  # Role configuration
  iam_role_name        = "github-actions-role"
  max_session_duration = 3600

  # Policy configuration
  attach_read_only_policy = false
  attach_admin_policy     = false

# iam_role_policy_arns = [
#   "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
# ]

  # add inline policies (principle of least privileges)
  iam_role_inline_policies = {
    github_ecr_push_permissions = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload",
            "ecr:PutImage"
          ]
          Resource = "*"
        }
      ]
    })
  }

  tags = {
    Environment = "dev"
    Project     = "GitHub OIDC"
  }
}