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
  description = "Stable AWS namespace for this tenant; this is not an Entra identifier."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.tenant_slug))
    error_message = "tenant_slug must contain lowercase letters, numbers, and internal hyphens."
  }
}

variable "entra_tenant_id" {
  description = "Microsoft Entra Directory (tenant) ID supplied by the Entra owner."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.entra_tenant_id))
    error_message = "entra_tenant_id must be a GUID."
  }
}

variable "gwchat_bff_client_id" {
  description = "Application (client) ID of the externally managed GWChat UI/BFF registration."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.gwchat_bff_client_id))
    error_message = "gwchat_bff_client_id must be a GUID."
  }
}

variable "agent_api_client_id" {
  description = "Application (client) ID of the externally managed GuideWell Agent API registration."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.agent_api_client_id))
    error_message = "agent_api_client_id must be a GUID."
  }
}

variable "m365_mcp_client_id" {
  description = "Application (client) ID of the externally managed M365 MCP API registration."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.m365_mcp_client_id))
    error_message = "m365_mcp_client_id must be a GUID."
  }
}

variable "agent_api_certificate_thumbprint" {
  description = "Base64url SHA-256 thumbprint of the AWS-generated Agent API KMS public certificate after Entra uploads it."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.agent_api_certificate_thumbprint == null || can(regex("^[A-Za-z0-9_-]{43}$", var.agent_api_certificate_thumbprint))
    error_message = "agent_api_certificate_thumbprint must be an unpadded base64url SHA-256 thumbprint."
  }
}

variable "m365_mcp_certificate_thumbprint" {
  description = "Base64url SHA-256 thumbprint of the AWS-generated M365 KMS public certificate after Entra uploads it."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.m365_mcp_certificate_thumbprint == null || can(regex("^[A-Za-z0-9_-]{43}$", var.m365_mcp_certificate_thumbprint))
    error_message = "m365_mcp_certificate_thumbprint must be an unpadded base64url SHA-256 thumbprint."
  }
}
