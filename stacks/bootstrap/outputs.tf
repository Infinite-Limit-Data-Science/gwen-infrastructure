output "state_bucket_name" {
  value = module.backend.bucket_name
}

output "state_kms_key_arn" {
  value = module.backend.kms_key_arn
}
