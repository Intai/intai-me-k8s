variable "project_name" {
  description = "Project name used for resource tagging"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the hosted zone"
  type        = string
}

variable "elastic_ips" {
  description = "Elastic IP addresses for DNS records"
  type        = list(string)
}
