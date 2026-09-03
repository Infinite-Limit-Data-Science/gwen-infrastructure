data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  safe_tenant        = replace(var.tenant_slug, "-", "_")
  name               = coalesce(var.gateway_name, "gwen-gateway-${var.tenant_slug}-${var.environment}")
  role_name          = coalesce(var.gateway_role_name, "gwen-gateway-${var.tenant_slug}-${var.environment}")
  policy_engine_name = coalesce(var.policy_engine_name, "gwen_policy_${local.safe_tenant}_${var.environment}")
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "gateway" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_bedrockagentcore_policy_engine" "this" {
  name        = local.policy_engine_name
  description = "Cedar authorization for the ${var.tenant_slug} GWen Gateway"
}

data "aws_iam_policy_document" "gateway" {
  statement {
    sid = "WorkloadIdentity"
    actions = [
      "bedrock-agentcore:GetWorkloadAccessToken",
      "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default",
      "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default/workload-identity/${local.name}-*",
    ]
  }

  statement {
    sid = "PolicyEvaluation"
    actions = [
      "bedrock-agentcore:AuthorizeAction",
      "bedrock-agentcore:PartiallyAuthorizeActions",
      "bedrock-agentcore:GetPolicyEngine",
    ]
    resources = [
      aws_bedrockagentcore_policy_engine.this.policy_engine_arn,
      "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:gateway/*",
    ]
  }
}

resource "aws_iam_role_policy" "gateway" {
  role   = aws_iam_role.gateway.id
  policy = data.aws_iam_policy_document.gateway.json
}

resource "aws_bedrockagentcore_gateway" "this" {
  name            = local.name
  description     = "Tenant-scoped governed GWen MCP Gateway"
  role_arn        = aws_iam_role.gateway.arn
  protocol_type   = "MCP"
  authorizer_type = "CUSTOM_JWT"
  exception_level = "DEBUG"

  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url    = var.discovery_url
      allowed_audience = [var.allowed_audience]
      allowed_scopes   = var.allowed_scopes

      custom_claim {
        inbound_token_claim_name       = "azp"
        inbound_token_claim_value_type = "STRING"

        authorizing_claim_match_value {
          claim_match_operator = "EQUALS"

          claim_match_value {
            match_value_string = var.approved_client_id
          }
        }
      }
    }
  }

  policy_engine_configuration {
    arn  = aws_bedrockagentcore_policy_engine.this.policy_engine_arn
    mode = var.policy_mode
  }

  protocol_configuration {
    mcp {
      instructions = "Expose only approved GWen MCP capabilities."

      streaming_configuration {
        enable_response_streaming = true
      }
    }
  }

  depends_on = [aws_iam_role_policy.gateway]
}

resource "aws_ssm_parameter" "id" {
  name  = "${var.parameter_prefix}/id"
  type  = "String"
  value = aws_bedrockagentcore_gateway.this.gateway_id
}

resource "aws_ssm_parameter" "arn" {
  name  = "${var.parameter_prefix}/arn"
  type  = "String"
  value = aws_bedrockagentcore_gateway.this.gateway_arn
}

resource "aws_ssm_parameter" "url" {
  name  = "${var.parameter_prefix}/url"
  type  = "String"
  value = aws_bedrockagentcore_gateway.this.gateway_url
}

resource "aws_ssm_parameter" "role_name" {
  name  = "${var.parameter_prefix}/role-name"
  type  = "String"
  value = aws_iam_role.gateway.name
}

resource "aws_ssm_parameter" "policy_engine_id" {
  name  = "${var.parameter_prefix}/policy-engine-id"
  type  = "String"
  value = aws_bedrockagentcore_policy_engine.this.policy_engine_id
}
