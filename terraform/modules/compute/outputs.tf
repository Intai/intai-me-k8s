output "instance_ids" {
  value = aws_instance.main[*].id
}

output "public_ips" {
  value = aws_instance.main[*].public_ip
}

output "elastic_ips" {
  value = aws_eip.main[*].public_ip
}
