# Terragrunt root for on-device platform experiments.

# Keep state in-repo under .run/ to avoid cloud backend requirements.
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    path = get_env(
      "TG_STATE_PATH",
      "${get_parent_terragrunt_dir()}/.run/${path_relative_to_include()}/terraform.tfstate"
    )
  }
}

locals {
  environment = "platform"
}

# Use OpenTofu by default for this context.
terraform_binary = "tofu"
