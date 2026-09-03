output "artifact_store" {
  value = {
    bucket_name              = module.artifacts.bucket_name
    table_name               = module.artifacts.table_name
    table_arn                = module.artifacts.table_arn
    kms_key_arn              = module.artifacts.kms_key_arn
    bff_upload_policy_arn    = module.artifacts.bff_upload_policy_arn
    document_read_policy_arn = module.artifacts.document_read_policy_arn
  }
}
