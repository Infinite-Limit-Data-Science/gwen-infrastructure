variable "environment" {
  type = string
}

variable "name" {
  type = string
}

variable "parameter_prefix" {
  type = string
}

variable "event_expiry_days" {
  type    = number
  default = 30

  validation {
    condition     = var.event_expiry_days >= 7 && var.event_expiry_days <= 365
    error_message = "event_expiry_days must be between 7 and 365."
  }
}

variable "enable_episodic" {
  type    = bool
  default = false
}
