variable "name" {
  description = "AgentCore Runtime name."
  type        = string
}

variable "description" {
  type = string
}

variable "ecr_repository_name" {
  type = string
}

variable "image_tag" {
  description = "Immutable image tag to deploy."
  type        = string
}

variable "deploy_runtime" {
  description = "Create the Runtime only after the immutable image tag exists in ECR."
  type        = bool
  default     = false
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}

variable "additional_policy_json" {
  description = "Workload-specific IAM policy JSON attached to the Runtime execution role."
  type        = string
}

variable "jwt_authorizer" {
  description = "Optional tenant-specific custom JWT authorizer. Null uses Runtime IAM authorization."
  type = object({
    discovery_url      = string
    allowed_audience   = list(string)
    allowed_scopes     = optional(list(string), [])
    custom_claim_name  = optional(string)
    custom_claim_value = optional(string)
  })
  default  = null
  nullable = true
}

variable "protocol" {
  description = "Runtime protocol. Use HTTP for agents and MCP for MCP servers."
  type        = string
  default     = "HTTP"

  validation {
    condition     = contains(["HTTP", "MCP"], var.protocol)
    error_message = "protocol must be HTTP or MCP."
  }
}

variable "request_header_allowlist" {
  type    = list(string)
  default = ["Authorization"]
}

variable "network_mode" {
  type    = string
  default = "PUBLIC"

  validation {
    condition     = contains(["PUBLIC", "VPC"], var.network_mode)
    error_message = "network_mode must be PUBLIC or VPC."
  }
}

variable "vpc_subnet_ids" {
  description = "Private subnet IDs used when network_mode is VPC."
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "Security group IDs used when network_mode is VPC."
  type        = list(string)
  default     = []
}

variable "idle_timeout_seconds" {
  type    = number
  default = 900
}

variable "max_lifetime_seconds" {
  type    = number
  default = 28800
}

variable "tags" {
  type    = map(string)
  default = {}
}
