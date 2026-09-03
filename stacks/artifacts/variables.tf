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

variable "retention_days" {
  type    = number
  default = 30
}

variable "force_destroy" {
  type    = bool
  default = false
}
