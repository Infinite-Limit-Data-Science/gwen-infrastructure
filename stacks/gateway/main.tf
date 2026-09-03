locals {
  identity_prefix = "/gwen/${var.environment}/identity/tenants/${var.tenant_slug}"
  gateway_prefix  = "/gwen/${var.environment}/platform/gateways/${var.tenant_slug}"
}

data "aws_ssm_parameter" "discovery_url" {
  name = "${local.identity_prefix}/discovery-url"
}

data "aws_ssm_parameter" "agent_api_client_id" {
  name = "${local.identity_prefix}/agent-api-client-id"
}

data "aws_ssm_parameter" "bff_client_id" {
  name = "${local.identity_prefix}/bff-client-id"
}

module "gateway" {
  source = "../../modules/agentcore-gateway"

  environment        = var.environment
  tenant_slug        = var.tenant_slug
  gateway_name       = var.gateway_name
  gateway_role_name  = var.gateway_role_name
  policy_engine_name = var.policy_engine_name
  discovery_url      = data.aws_ssm_parameter.discovery_url.value
  allowed_audience   = data.aws_ssm_parameter.agent_api_client_id.value
  allowed_scopes     = ["agent.invoke"]
  approved_client_id = data.aws_ssm_parameter.bff_client_id.value
  parameter_prefix   = local.gateway_prefix
  policy_mode        = var.policy_mode
}
