output "log_group_name" {
  value = aws_cloudwatch_log_group.platform.name
}

output "kms_key_arn" {
  value = aws_kms_key.logs.arn
}
