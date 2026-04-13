variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "c8i.large"
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "vm_disk_gb" {
  type = number
}
