### Backend ###
# S3
###############

terraform {
  backend "s3" {
    bucket = "cloudgeeks-ca-terraform"
    key    = "env/dev/cloudgeeks-dev-oidc-github.tfstate"
    region = "us-east-1"
    # dynamodb_table = "cloudgeeksca-dev-terraform-backend-state-lock"
  }
}