terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.33"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.8"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
