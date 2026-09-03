variable "aws_profile" {
  type    = string
  default = "default"
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

variable "bedrock_prompt_model_id" {
  description = "Approved model metadata required by Bedrock Prompt Management."
  type        = string
}

variable "enable_document_target" {
  type    = bool
  default = true
}

variable "enable_web_target" {
  type    = bool
  default = true
}

variable "reconcile_revision" {
  type    = string
  default = "1"
}
