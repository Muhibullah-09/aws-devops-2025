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



# Step 1: Check for existing Route 53 hosted zone
data "aws_route53_zone" "existing" {
  name         = var.domain_name
  private_zone = false
}

# Create a new hosted zone if it doesn't exist
resource "aws_route53_zone" "new" {
  count = length(data.aws_route53_zone.existing.zone_id) == 0 ? 1 : 0
  name  = var.domain_name

  tags = {
    Name = "wordpress-hosted-zone"
  }
}

# Determine which hosted zone to use (existing or new)
locals {
  hosted_zone_id = length(data.aws_route53_zone.existing.zone_id) > 0 ? data.aws_route53_zone.existing.zone_id : aws_route53_zone.new[0].zone_id
  full_domain    = "${var.subdomain}.${var.domain_name}" # e.g., wp.sawarikar.com
}

# Step 2: Create a new ACM certificate (no data source needed)
resource "aws_acm_certificate" "cert" {
  domain_name       = local.full_domain
  validation_method = "DNS"

  tags = {
    Name = "wordpress-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create DNS records for ACM validation
resource "aws_route53_record" "cert_validation" {
  zone_id = local.hosted_zone_id
  name    = tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_type
  ttl     = 60
  records = [tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_value]
}

# Validate the certificate
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}

# Determine the certificate ARN (always use the validated one)
locals {
  certificate_arn = aws_acm_certificate_validation.cert.certificate_arn
}

# Step 3: Create an alias record to point to the ALB
resource "aws_route53_record" "alb_alias" {
  zone_id = local.hosted_zone_id
  name    = var.subdomain
  type    = "A"

  alias {
    name                   = module.ecs.alb_dns_name
    zone_id                = module.ecs.alb_zone_id
    evaluate_target_health = true
  }
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
  task_role_arn            = module.iam.task_role_arn # Pass the task role ARN
  rds_cluster_endpoint     = module.rds.rds_cluster_endpoint
  secret_arn               = module.rds.secret_arn
  efs_file_system_id       = module.efs.efs_file_system_id
  efs_access_point_id      = module.efs.efs_access_point_id
  aws_region               = var.aws_region
  acm_certificate_arn      = local.certificate_arn
}

output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}
