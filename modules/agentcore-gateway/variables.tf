variable "environment" {
  type = string
}

variable "tenant_slug" {
  type = string
}

variable "gateway_name" {
  type    = string
  default = null
}

variable "gateway_role_name" {
  type    = string
  default = null
}

variable "policy_engine_name" {
  type    = string
  default = null
}

variable "discovery_url" {
  type = string
}

variable "allowed_audience" {
  type = string
}

variable "allowed_scopes" {
  type    = list(string)
  default = ["agent.invoke"]
}

variable "approved_client_id" {
  type = string
}

variable "parameter_prefix" {
  type = string
}

variable "policy_mode" {
  type    = string
  default = "ENFORCE"

  validation {
    condition     = contains(["ENFORCE", "LOG_ONLY"], var.policy_mode)
    error_message = "policy_mode must be ENFORCE or LOG_ONLY."
  }
}
