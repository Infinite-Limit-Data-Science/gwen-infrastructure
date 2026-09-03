resource "aws_kms_key" "logs" {
  description             = "Encrypt shared GWen platform logs"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "logs" {
  name          = "alias/gwen-observability-${var.environment}"
  target_key_id = aws_kms_key.logs.key_id
}

resource "aws_cloudwatch_log_group" "platform" {
  name              = "/gwen/${var.environment}/platform"
  retention_in_days = var.retention_days
  kms_key_id        = aws_kms_key.logs.arn
}

resource "aws_ssm_parameter" "log_group" {
  name  = "${var.parameter_prefix}/log-group"
  type  = "String"
  value = aws_cloudwatch_log_group.platform.name
}

resource "aws_ssm_parameter" "kms_key_arn" {
  name  = "${var.parameter_prefix}/kms-key-arn"
  type  = "String"
  value = aws_kms_key.logs.arn
}
