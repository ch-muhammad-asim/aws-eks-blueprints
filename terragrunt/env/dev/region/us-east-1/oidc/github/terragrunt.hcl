include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../../../modules//oidc/github"
}

inputs = {

  github_repos = [
    "quickbooks2018/github-oidc-aws",
  ]

}