variable "environment" {
  type = string
}

variable "retention_days" {
  type    = number
  default = 30
}

variable "parameter_prefix" {
  type = string
}
