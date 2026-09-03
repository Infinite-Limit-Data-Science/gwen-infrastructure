locals {
  identity_prefix = "/gwen/${var.environment}/identity/tenants/${var.tenant_slug}"
  discovery_url   = "https://login.microsoftonline.com/${var.entra_tenant_id}/v2.0/.well-known/openid-configuration"
}

resource "aws_kms_key" "agent_api_signing" {
  description              = "Private-key JWT signing key for ${var.tenant_slug} Agent API OBO"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "RSA_2048"
  deletion_window_in_days  = 30

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "agent_api_signing" {
  name          = "alias/gwen-agent-api-obo-${var.tenant_slug}-${var.environment}"
  target_key_id = aws_kms_key.agent_api_signing.key_id
}

resource "aws_kms_key" "m365_signing" {
  description              = "Private-key JWT signing key for ${var.tenant_slug} M365 Graph OBO"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "RSA_2048"
  deletion_window_in_days  = 30

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "m365_signing" {
  name          = "alias/gwen-m365-obo-${var.tenant_slug}-${var.environment}"
  target_key_id = aws_kms_key.m365_signing.key_id
}

resource "aws_ssm_parameter" "entra_tenant_id" {
  name  = "${local.identity_prefix}/tenant-id"
  type  = "String"
  value = var.entra_tenant_id
}

resource "aws_ssm_parameter" "discovery_url" {
  name  = "${local.identity_prefix}/discovery-url"
  type  = "String"
  value = local.discovery_url
}

resource "aws_ssm_parameter" "bff_client_id" {
  name  = "${local.identity_prefix}/bff-client-id"
  type  = "String"
  value = var.gwchat_bff_client_id
}

resource "aws_ssm_parameter" "agent_api_client_id" {
  name  = "${local.identity_prefix}/agent-api-client-id"
  type  = "String"
  value = var.agent_api_client_id
}

resource "aws_ssm_parameter" "m365_mcp_client_id" {
  name  = "${local.identity_prefix}/m365-mcp-client-id"
  type  = "String"
  value = var.m365_mcp_client_id
}

resource "aws_ssm_parameter" "agent_api_kms_key_arn" {
  name  = "${local.identity_prefix}/agent-api-kms-key-arn"
  type  = "String"
  value = aws_kms_key.agent_api_signing.arn
}

resource "aws_ssm_parameter" "m365_kms_key_arn" {
  name  = "${local.identity_prefix}/m365-kms-key-arn"
  type  = "String"
  value = aws_kms_key.m365_signing.arn
}

resource "aws_ssm_parameter" "agent_api_thumbprint" {
  count = var.agent_api_certificate_thumbprint == null ? 0 : 1

  name  = "${local.identity_prefix}/agent-api-certificate-thumbprint"
  type  = "String"
  value = var.agent_api_certificate_thumbprint
}

resource "aws_ssm_parameter" "m365_thumbprint" {
  count = var.m365_mcp_certificate_thumbprint == null ? 0 : 1

  name  = "${local.identity_prefix}/m365-certificate-thumbprint"
  type  = "String"
  value = var.m365_mcp_certificate_thumbprint
}
