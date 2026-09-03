output "observability" {
  value = {
    log_group_name = module.observability.log_group_name
    kms_key_arn    = module.observability.kms_key_arn
  }
}
