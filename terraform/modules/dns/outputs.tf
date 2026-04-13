output "zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "nameservers" {
  description = "Nameservers to configure at the domain registrar"
  value       = aws_route53_zone.main.name_servers
}

output "health_check_ids" {
  description = "Route 53 health check IDs"
  value       = aws_route53_health_check.main[*].id
}
