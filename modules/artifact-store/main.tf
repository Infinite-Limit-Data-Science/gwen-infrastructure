data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  bucket_name = "gwen-agentcore-artifacts-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-${var.environment}"
}

resource "aws_kms_key" "artifacts" {
  description             = "Encrypt GWen conversation artifacts and authorization records"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "artifacts" {
  name          = "alias/gwen-agentcore-artifacts-${var.environment}"
  target_key_id = aws_kms_key.artifacts.key_id
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.artifacts.arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-conversation-artifacts"
    status = "Enabled"

    filter {
      prefix = "agentcore-invocations/"
    }

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_dynamodb_table" "artifacts" {
  name         = "gwen-conversation-artifacts-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "conversation_scope"
  range_key    = "artifact_id"

  attribute {
    name = "conversation_scope"
    type = "S"
  }

  attribute {
    name = "artifact_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.artifacts.arn
  }

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "bff_upload" {
  statement {
    sid       = "RegisterConversationArtifacts"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.artifacts.arn]
  }

  statement {
    sid = "UploadInvocationArtifacts"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/agentcore-invocations/*"]
  }

  statement {
    sid       = "ListArtifactMultipartUploads"
    actions   = ["s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.artifacts.arn]
  }

  statement {
    sid     = "EncryptInvocationArtifacts"
    actions = ["kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [
      aws_kms_key.artifacts.arn,
    ]
  }
}

resource "aws_iam_policy" "bff_upload" {
  name   = "gwen-bff-agentcore-artifact-upload-${var.environment}"
  policy = data.aws_iam_policy_document.bff_upload.json

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "document_read" {
  statement {
    sid       = "ResolveConversationArtifacts"
    actions   = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.artifacts.arn]
  }

  statement {
    sid       = "ReadConversationArtifactBytes"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.artifacts.arn}/agentcore-invocations/*"]
  }

  statement {
    sid       = "DecryptConversationArtifactBytes"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.artifacts.arn]
  }
}

resource "aws_iam_policy" "document_read" {
  name   = "gwen-document-artifact-read-${var.environment}"
  policy = data.aws_iam_policy_document.document_read.json

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "bucket" {
  name  = "${var.parameter_prefix}/bucket"
  type  = "String"
  value = aws_s3_bucket.artifacts.id
}

resource "aws_ssm_parameter" "table" {
  name  = "${var.parameter_prefix}/table"
  type  = "String"
  value = aws_dynamodb_table.artifacts.name
}

resource "aws_ssm_parameter" "kms_key_arn" {
  name  = "${var.parameter_prefix}/kms-key-arn"
  type  = "String"
  value = aws_kms_key.artifacts.arn
}

resource "aws_ssm_parameter" "bff_policy_arn" {
  name  = "${var.parameter_prefix}/bff-upload-policy-arn"
  type  = "String"
  value = aws_iam_policy.bff_upload.arn
}

resource "aws_ssm_parameter" "document_policy_arn" {
  name  = "${var.parameter_prefix}/document-read-policy-arn"
  type  = "String"
  value = aws_iam_policy.document_read.arn
}
