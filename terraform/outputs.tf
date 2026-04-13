output "instance_id" {
  value = module.compute.instance_id
}

output "public_ip" {
  value = module.compute.public_ip
}

output "elastic_ip" {
  value = module.compute.elastic_ip
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "nameservers" {
  value = module.dns.nameservers
}
