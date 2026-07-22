terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  cluster_name = "pdf-service-dev"
}

module "vpc" {
  source       = "../../modules/vpc"
  cluster_name = local.cluster_name
  azs          = var.azs
}

module "ecr" {
  source     = "../../modules/ecr"
  prefix     = "pdf-service"
  repo_names = ["api", "worker", "frontend"]
}

module "eks" {
  source       = "../../modules/eks"
  cluster_name = local.cluster_name

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  # Small + spot to keep this cheap -- see infra/README.md for cost notes.
  node_instance_types = ["t3.small"]
  node_desired_size   = 2
  node_min_size       = 1
  node_max_size       = 3
}
