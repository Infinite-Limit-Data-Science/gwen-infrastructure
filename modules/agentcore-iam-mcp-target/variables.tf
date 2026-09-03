variable "aws_profile" {
  type    = string
  default = ""
}

variable "aws_region" {
  type = string
}

variable "gateway_id" {
  type = string
}

variable "gateway_arn" {
  type = string
}

variable "gateway_role_name" {
  type = string
}

variable "policy_engine_id" {
  type = string
}

variable "runtime_arn" {
  type = string
}

variable "runtime_endpoint" {
  type = string
}

variable "target_name" {
  type = string
}

variable "resource_name_suffix" {
  description = "Environment/tenant suffix that keeps IAM and Cedar names unique."
  type        = string
}

variable "target_description" {
  type = string
}

variable "target_parameter_name" {
  type = string
}

variable "allowed_request_headers" {
  type    = list(string)
  default = []
}

variable "reconcile_revision" {
  type    = string
  default = "1"
}
