variable "environment" {
  type = string
}

variable "parameter_prefix" {
  type = string
}

variable "retention_days" {
  type    = number
  default = 30

  validation {
    condition     = var.retention_days >= 1
    error_message = "retention_days must be at least one day."
  }
}

variable "force_destroy" {
  type    = bool
  default = false
}
