terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "./modules/vpc"
}

module "iam" {
  source = "./modules/iam"
}

module "rds" {
  source               = "./modules/rds"
  vpc_id               = module.vpc.vpc_id
  db_subnet_group_name = module.vpc.db_subnet_group_name
  sg_rds_id            = module.vpc.sg_rds_id
}

module "efs" {
  source             = "./modules/efs"
  private_subnet_ids = module.vpc.private_subnet_ids
  sg_efs_id          = module.vpc.sg_efs_id
}

module "ecs" {
  source                   = "./modules/ecs"
  vpc_id                   = module.vpc.vpc_id
  public_subnet_ids        = module.vpc.public_subnet_ids
  private_subnet_ids       = module.vpc.private_subnet_ids
  sg_alb_id                = module.vpc.sg_alb_id
  sg_ecs_id                = module.vpc.sg_ecs_id
  task_execution_role_arn  = module.iam.task_execution_role_arn
  task_execution_role_name = module.iam.task_execution_role_name
  rds_cluster_endpoint     = module.rds.rds_cluster_endpoint
  secret_arn               = module.rds.secret_arn
  efs_file_system_id       = module.efs.efs_file_system_id
  efs_access_point_id      = module.efs.efs_access_point_id # Pass the access point ID
  aws_region               = var.aws_region
}

output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}
