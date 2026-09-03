data "aws_iam_policy_document" "gateway_invoke" {
  statement {
    sid     = "InvokeMcpRuntime"
    actions = ["bedrock-agentcore:InvokeAgentRuntime"]
    resources = [
      var.runtime_arn,
      "${var.runtime_arn}/runtime-endpoint/DEFAULT",
    ]
  }
}

locals {
  policy_name_seed = "Permit${var.target_name}${var.resource_name_suffix}Calls"
  policy_name = (
    length(local.policy_name_seed) <= 48
    ? local.policy_name_seed
    : "${substr(local.policy_name_seed, 0, 39)}_${substr(md5(local.policy_name_seed), 0, 8)}"
  )
}

resource "aws_iam_policy" "gateway_invoke" {
  name   = "gwen-${lower(var.target_name)}-${var.resource_name_suffix}-invoke"
  policy = data.aws_iam_policy_document.gateway_invoke.json
}

resource "aws_iam_role_policy_attachment" "gateway_invoke" {
  role       = var.gateway_role_name
  policy_arn = aws_iam_policy.gateway_invoke.arn
}

resource "aws_bedrockagentcore_policy" "target" {
  name             = local.policy_name
  description      = "Permit approved calls to ${var.target_name}"
  policy_engine_id = var.policy_engine_id
  validation_mode  = "IGNORE_ALL_FINDINGS"

  definition {
    cedar {
      statement = <<-CEDAR
        permit(
          principal,
          action,
          resource == AgentCore::Gateway::"${var.gateway_arn}"
        );
      CEDAR
    }
  }
}

resource "terraform_data" "target" {
  input = {
    headers          = jsonencode(var.allowed_request_headers)
    revision         = var.reconcile_revision
    runtime_arn      = var.runtime_arn
    runtime_endpoint = var.runtime_endpoint
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/reconcile_target.sh"

    environment = {
      ALLOWED_REQUEST_HEADERS = jsonencode(var.allowed_request_headers)
      AWS_PROFILE             = var.aws_profile
      AWS_REGION              = var.aws_region
      GATEWAY_ID              = var.gateway_id
      RUNTIME_ENDPOINT        = var.runtime_endpoint
      TARGET_DESCRIPTION      = var.target_description
      TARGET_NAME             = var.target_name
      TARGET_PARAMETER_NAME   = var.target_parameter_name
    }
  }

  depends_on = [
    aws_bedrockagentcore_policy.target,
    aws_iam_role_policy_attachment.gateway_invoke,
  ]
}

data "aws_ssm_parameter" "target_id" {
  name       = var.target_parameter_name
  depends_on = [terraform_data.target]
}
