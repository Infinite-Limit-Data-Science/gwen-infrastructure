output "target_id" {
  value = nonsensitive(data.aws_ssm_parameter.target_id.value)
}
