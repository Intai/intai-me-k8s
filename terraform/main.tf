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
  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.security.instance_sg_id
  vm_disk_gb        = var.vm_disk_gb
  server_count      = var.server_count
}

module "dns" {
  source = "./modules/dns"

  project_name = var.project_name
  environment  = var.environment
  domain_name  = var.domain_name
  elastic_ips  = module.compute.elastic_ips
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/hosts.yml"
  content = templatefile("${path.module}/templates/hosts.yml.tftpl", {
    servers = [for i, eip in module.compute.elastic_ips : {
      name      = "server${i + 1}"
      ip        = eip
      vm_ip     = "192.168.122.${10 + i}"
      wg_ip     = "10.10.0.${1 + i}"
      node_name = "node${i + 1}"
    }]
  })
}
