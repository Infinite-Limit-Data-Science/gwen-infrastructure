variable "name" {
  type = string
}

variable "description" {
  type    = string
  default = "Approved GWen invocation-scoped specialist agents."
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_profile" {
  type    = string
  default = ""
}

variable "parameter_name" {
  type = string
}

variable "reconcile_revision" {
  description = "Change this value to force Registry reconciliation."
  type        = string
  default     = "1"
}
