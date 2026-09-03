data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_ecr_repository" "runtime" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
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

resource "aws_iam_role" "runtime" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "base" {
  statement {
    sid = "PullRuntimeImage"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.runtime.arn]
  }

  statement {
    sid       = "AuthenticateToEcr"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "RuntimeObservability"
    actions = [
      "cloudwatch:PutMetricData",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
      "xray:PutTelemetryRecords",
      "xray:PutTraceSegments",
    ]
    resources = ["*"]
  }

  statement {
    sid = "CreateRuntimeLogGroup"
    actions = [
      "logs:CreateLogGroup",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*",
    ]
  }

  statement {
    sid = "WriteRuntimeLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*:log-stream:*",
    ]
  }
}

resource "aws_iam_role_policy" "base" {
  name   = "${var.name}-base"
  role   = aws_iam_role.runtime.id
  policy = data.aws_iam_policy_document.base.json
}

resource "aws_iam_role_policy" "additional" {
  name   = "${var.name}-workload"
  role   = aws_iam_role.runtime.id
  policy = var.additional_policy_json
}

moved {
  from = aws_iam_role_policy.additional[0]
  to   = aws_iam_role_policy.additional
}

resource "aws_bedrockagentcore_agent_runtime" "this" {
  count = var.deploy_runtime ? 1 : 0

  agent_runtime_name = var.name
  description        = var.description
  role_arn           = aws_iam_role.runtime.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${aws_ecr_repository.runtime.repository_url}:${var.image_tag}"
    }
  }

  dynamic "authorizer_configuration" {
    for_each = var.jwt_authorizer == null ? [] : [var.jwt_authorizer]

    content {
      custom_jwt_authorizer {
        discovery_url    = authorizer_configuration.value.discovery_url
        allowed_audience = authorizer_configuration.value.allowed_audience
        allowed_scopes = (
          length(authorizer_configuration.value.allowed_scopes) == 0
          ? null
          : authorizer_configuration.value.allowed_scopes
        )

        dynamic "custom_claim" {
          for_each = (
            authorizer_configuration.value.custom_claim_name == null ||
            authorizer_configuration.value.custom_claim_value == null
          ) ? [] : [authorizer_configuration.value]

          content {
            inbound_token_claim_name       = custom_claim.value.custom_claim_name
            inbound_token_claim_value_type = "STRING"

            authorizing_claim_match_value {
              claim_match_operator = "EQUALS"

              claim_match_value {
                match_value_string = custom_claim.value.custom_claim_value
              }
            }
          }
        }
      }
    }
  }

  environment_variables = var.environment_variables

  lifecycle_configuration {
    idle_runtime_session_timeout = var.idle_timeout_seconds
    max_lifetime                 = var.max_lifetime_seconds
  }

  network_configuration {
    network_mode = var.network_mode

    dynamic "network_mode_config" {
      for_each = var.network_mode == "VPC" ? [1] : []

      content {
        subnets         = var.vpc_subnet_ids
        security_groups = var.vpc_security_group_ids
      }
    }
  }

  lifecycle {
    precondition {
      condition = (
        var.network_mode != "VPC" ||
        (length(var.vpc_subnet_ids) >= 2 && length(var.vpc_security_group_ids) > 0)
      )
      error_message = "VPC mode requires at least two private subnets and one security group."
    }
  }

  dynamic "protocol_configuration" {
    for_each = var.protocol == "MCP" ? [1] : []

    content {
      server_protocol = "MCP"
    }
  }

  dynamic "request_header_configuration" {
    for_each = length(var.request_header_allowlist) == 0 ? [] : [1]

    content {
      request_header_allowlist = var.request_header_allowlist
    }
  }

  depends_on = [aws_iam_role_policy.base, aws_iam_role_policy.additional]
}

locals {
  endpoint = var.deploy_runtime ? "https://bedrock-agentcore.${data.aws_region.current.region}.amazonaws.com/runtimes/${urlencode(aws_bedrockagentcore_agent_runtime.this[0].agent_runtime_arn)}/invocations?qualifier=DEFAULT" : null
}
