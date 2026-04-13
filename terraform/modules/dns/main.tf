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

resource "aws_route53_health_check" "main" {
  count             = length(var.elastic_ips)
  ip_address        = var.elastic_ips[count.index]
  port              = 443
  type              = "TCP"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name        = "${var.project_name}-hc-${count.index + 1}"
    Environment = var.environment
  }
}

resource "aws_route53_record" "a" {
  count           = length(var.elastic_ips)
  zone_id         = aws_route53_zone.main.zone_id
  name            = var.domain_name
  type            = "A"
  ttl             = 60
  records         = [var.elastic_ips[count.index]]
  set_identifier  = "server-${count.index + 1}"
  health_check_id = aws_route53_health_check.main[count.index].id

  weighted_routing_policy {
    weight = 100
  }
}

resource "aws_route53_record" "a_www" {
  count           = length(var.elastic_ips)
  zone_id         = aws_route53_zone.main.zone_id
  name            = "www.${var.domain_name}"
  type            = "A"
  ttl             = 60
  records         = [var.elastic_ips[count.index]]
  set_identifier  = "server-${count.index + 1}"
  health_check_id = aws_route53_health_check.main[count.index].id

  weighted_routing_policy {
    weight = 100
  }
}
