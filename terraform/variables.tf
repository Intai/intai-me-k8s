variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "project_name" {
  type    = string
  default = "intai-me-k8s"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "domain_name" {
  type    = string
  default = "intai.me"
}

variable "instance_type" {
  type    = string
  default = "c8i.large"
}

variable "vm_disk_gb" {
  type    = number
  default = 30
}
