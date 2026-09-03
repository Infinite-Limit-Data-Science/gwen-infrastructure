terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.61"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region

  default_tags {
    tags = {
      Application = "GWen"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Stack       = "gateway"
      Tenant      = var.tenant_slug
    }
  }
}
