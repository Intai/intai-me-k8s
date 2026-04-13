module "vpc" {
  source = "./modules/vpc"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
}

module "security" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
}

module "compute" {
  source = "./modules/compute"

  project_name      = var.project_name
  environment       = var.environment
  instance_type     = var.instance_type
  subnet_id         = module.vpc.public_subnet_ids[0]
  security_group_id = module.security.instance_sg_id
  vm_disk_gb        = var.vm_disk_gb
}

module "dns" {
  source = "./modules/dns"

  project_name = var.project_name
  environment  = var.environment
  domain_name  = var.domain_name
  elastic_ip   = module.compute.elastic_ip
}
