variable "bucket_name" {
  description = "Globally unique S3 bucket used for Terraform state."
  type        = string
}

variable "kms_alias" {
  description = "Alias for the Terraform state encryption key."
  type        = string
  default     = "alias/gwen-terraform-state"
}

variable "force_destroy" {
  description = "Allow deleting state objects. Keep false outside disposable local testing."
  type        = bool
  default     = false
}
