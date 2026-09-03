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

variable "event_expiry_days" {
  type    = number
  default = 30
}

variable "enable_episodic" {
  type    = bool
  default = false
}
