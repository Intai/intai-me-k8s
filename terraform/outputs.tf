output "instance_ids" {
  value = module.compute.instance_ids
}

output "public_ips" {
  value = module.compute.public_ips
}

output "elastic_ips" {
  value = module.compute.elastic_ips
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "nameservers" {
  value = module.dns.nameservers
}
