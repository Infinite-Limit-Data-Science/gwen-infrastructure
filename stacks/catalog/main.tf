locals {
  gateway_prefix  = "/gwen/${var.environment}/platform/gateways/${var.tenant_slug}"
  registry_prefix = "/gwen/${var.environment}/platform/registries/${var.tenant_slug}"
  target_prefix   = "/gwen/${var.environment}/targets/${var.tenant_slug}"
}

data "aws_ssm_parameter" "gateway_url" {
  name = "${local.gateway_prefix}/url"
}

data "aws_ssm_parameter" "gateway_id" {
  name = "${local.gateway_prefix}/id"
}

data "aws_ssm_parameter" "registry_id" {
  name = "${local.registry_prefix}/id"
}

data "aws_ssm_parameter" "m365_target_id" {
  name = "${local.target_prefix}/m365/id"
}

data "aws_ssm_parameter" "document_target_id" {
  count = var.enable_document_target ? 1 : 0
  name  = "${local.target_prefix}/document-intelligence/id"
}

data "aws_ssm_parameter" "web_target_id" {
  count = var.enable_web_target ? 1 : 0
  name  = "${local.target_prefix}/web-grounding/id"
}

resource "terraform_data" "catalog" {
  triggers_replace = {
    document_target_id = var.enable_document_target ? data.aws_ssm_parameter.document_target_id[0].value : ""
    gateway_url        = data.aws_ssm_parameter.gateway_url.value
    m365_target_id     = data.aws_ssm_parameter.m365_target_id.value
    model_id           = var.bedrock_prompt_model_id
    registry_id        = data.aws_ssm_parameter.registry_id.value
    revision           = var.reconcile_revision
    web_target_id      = var.enable_web_target ? data.aws_ssm_parameter.web_target_id[0].value : ""
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/reconcile-catalog.sh"

    environment = {
      AWS_PROFILE             = var.aws_profile
      AWS_REGION              = var.aws_region
      BEDROCK_PROMPT_MODEL_ID = var.bedrock_prompt_model_id
      DOCUMENT_GATEWAY_URL    = var.enable_document_target ? data.aws_ssm_parameter.gateway_url.value : ""
      DOCUMENT_TARGET_ID      = var.enable_document_target ? data.aws_ssm_parameter.document_target_id[0].value : ""
      ENVIRONMENT             = var.environment
      GATEWAY_ID              = data.aws_ssm_parameter.gateway_id.value
      GATEWAY_URL             = data.aws_ssm_parameter.gateway_url.value
      M365_TARGET_ID          = data.aws_ssm_parameter.m365_target_id.value
      REGISTRY_ID             = data.aws_ssm_parameter.registry_id.value
      TENANT_SLUG             = var.tenant_slug
      WEB_GATEWAY_URL         = var.enable_web_target ? data.aws_ssm_parameter.gateway_url.value : ""
      WEB_TARGET_ID           = var.enable_web_target ? data.aws_ssm_parameter.web_target_id[0].value : ""
    }
  }
}
