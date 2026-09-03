output "bucket_name" {
  value = aws_s3_bucket.artifacts.id
}

output "table_name" {
  value = aws_dynamodb_table.artifacts.name
}

output "table_arn" {
  value = aws_dynamodb_table.artifacts.arn
}

output "kms_key_arn" {
  value = aws_kms_key.artifacts.arn
}

output "bff_upload_policy_arn" {
  value = aws_iam_policy.bff_upload.arn
}

output "document_read_policy_arn" {
  value = aws_iam_policy.document_read.arn
}
