include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//oidc/github"
}

inputs = {

  github_repos = [
    "quickbooks2018/github-oidc-aws",
  ]

}