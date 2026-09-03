output "id" {
  value     = data.aws_ssm_parameter.registry_id.value
  sensitive = true
}
