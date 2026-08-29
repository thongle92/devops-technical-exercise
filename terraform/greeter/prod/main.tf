terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "kind-greeter"
  }
}

locals {
  # requires running terraform from inside this directory (cd here first) -
  # `terraform -chdir=...` from elsewhere resolves path.cwd to the wrong dir
  environment = basename(path.cwd)
}

module "greeter" {
  source = "../../modules/greeter"

  release_name  = "greeter-${local.environment}"
  namespace     = local.environment
  greeting_name = "${var.greeting_name} (${local.environment})"
  replica_count = var.replica_count
  node_port     = 30081
}
