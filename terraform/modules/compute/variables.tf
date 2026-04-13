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

variable "security_group_id" {
  type = string
}

variable "vm_disk_gb" {
  type = number
}

variable "server_count" {
  type    = number
  default = 1
}

variable "subnet_ids" {
  type = list(string)
}
