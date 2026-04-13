variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_az_count" {
  description = "Number of availability zones / public subnets to create"
  type        = number
  default     = 2
}
