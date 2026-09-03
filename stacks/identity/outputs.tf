output "identity" {
  value = {
    tenant_id             = var.entra_tenant_id
    discovery_url         = local.discovery_url
    bff_client_id         = var.gwchat_bff_client_id
    agent_api_client_id   = var.agent_api_client_id
    m365_mcp_client_id    = var.m365_mcp_client_id
    agent_api_kms_key_arn = aws_kms_key.agent_api_signing.arn
    m365_kms_key_arn      = aws_kms_key.m365_signing.arn
  }
}

output "agent_api_signing_key_arn" {
  value = aws_kms_key.agent_api_signing.arn
}

output "m365_signing_key_arn" {
  value = aws_kms_key.m365_signing.arn
}
