terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "ecr" {
  source          = "../../modules/ecr"
  repository_name = "todo-app"
}

module "oidc" {
  source             = "../../modules/oidc"
  github_repository  = var.github_repository
  ecr_repository_arn = module.ecr.repository_arn
}

module "lightsail" {
  source            = "../../modules/lightsail"
  instance_name     = "todo-app-prod"
  availability_zone = "${var.aws_region}a"
  key_pair_name     = var.key_pair_name
}
