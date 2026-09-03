variable "aws_profile" {
  type    = string
  default = "atlantic_genetics"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "tenant_slug" {
  type = string
}

variable "registry_name" {
  description = "Optional existing Registry name to preserve during state migration."
  type        = string
  default     = null
}

variable "reconcile_revision" {
  type    = string
  default = "1"
}
