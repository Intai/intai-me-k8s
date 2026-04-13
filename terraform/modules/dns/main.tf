locals {
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_route53_zone" "main" {
  name = var.domain_name
  tags = local.tags
}

resource "aws_route53_record" "a" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [var.elastic_ip]
}

resource "aws_route53_record" "a_www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [var.elastic_ip]
}
