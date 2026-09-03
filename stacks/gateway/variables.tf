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

variable "gateway_name" {
  description = "Optional existing Gateway name to preserve during state migration."
  type        = string
  default     = null
}

variable "gateway_role_name" {
  description = "Optional existing Gateway IAM role name to preserve during state migration."
  type        = string
  default     = null
}

variable "policy_engine_name" {
  description = "Optional existing policy engine name to preserve during state migration."
  type        = string
  default     = null
}

variable "policy_mode" {
  type    = string
  default = "ENFORCE"
}
