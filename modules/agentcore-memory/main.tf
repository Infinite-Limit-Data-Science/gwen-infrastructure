data "aws_partition" "current" {}

resource "aws_kms_key" "memory" {
  description             = "Encrypt GWen AgentCore Memory"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "memory" {
  name          = "alias/gwen-agentcore-memory-${var.environment}"
  target_key_id = aws_kms_key.memory.key_id
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

resource "aws_iam_role" "memory" {
  name               = "gwen-agentcore-memory-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "model_inference" {
  role       = aws_iam_role.memory.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy"
}

data "aws_iam_policy_document" "memory" {
  statement {
    sid       = "MemoryEncryption"
    actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.memory.arn]
  }
}

resource "aws_iam_role_policy" "memory" {
  role   = aws_iam_role.memory.id
  policy = data.aws_iam_policy_document.memory.json
}

resource "aws_bedrockagentcore_memory" "this" {
  name                      = var.name
  description               = "Conversation memory shared by approved GWen workloads"
  event_expiry_duration     = var.event_expiry_days
  encryption_key_arn        = aws_kms_key.memory.arn
  memory_execution_role_arn = aws_iam_role.memory.arn

  depends_on = [
    aws_iam_role_policy.memory,
    aws_iam_role_policy_attachment.model_inference,
  ]
}

resource "aws_bedrockagentcore_memory_strategy" "summarization" {
  name                = "primary_session_summary"
  memory_id           = aws_bedrockagentcore_memory.this.id
  type                = "SUMMARIZATION"
  description         = "Condense a conversation while preserving durable context"
  namespace_templates = ["/actors/{actorId}/sessions/{sessionId}/summaries/"]
}

resource "aws_bedrockagentcore_memory_strategy" "semantic" {
  name                = "primary_semantic_facts"
  memory_id           = aws_bedrockagentcore_memory.this.id
  type                = "SEMANTIC"
  description         = "Extract durable user-scoped semantic facts"
  namespace_templates = ["/actors/{actorId}/facts/"]
}

resource "aws_bedrockagentcore_memory_strategy" "preference" {
  name                = "primary_user_preferences"
  memory_id           = aws_bedrockagentcore_memory.this.id
  type                = "USER_PREFERENCE"
  description         = "Extract durable user preferences"
  namespace_templates = ["/actors/{actorId}/preferences/"]
}

resource "aws_bedrockagentcore_memory_strategy" "episodic" {
  count = var.enable_episodic ? 1 : 0

  name                = "primary_episodes"
  memory_id           = aws_bedrockagentcore_memory.this.id
  type                = "EPISODIC"
  description         = "Retain reusable user-scoped interaction episodes"
  namespace_templates = ["/actors/{actorId}/episodes/"]

  reflection_configuration {
    namespace_templates = ["/actors/{actorId}/episodes/"]
  }
}

resource "aws_ssm_parameter" "id" {
  name  = "${var.parameter_prefix}/id"
  type  = "String"
  value = aws_bedrockagentcore_memory.this.id
}

resource "aws_ssm_parameter" "arn" {
  name  = "${var.parameter_prefix}/arn"
  type  = "String"
  value = aws_bedrockagentcore_memory.this.arn
}

resource "aws_ssm_parameter" "kms_key_arn" {
  name  = "${var.parameter_prefix}/kms-key-arn"
  type  = "String"
  value = aws_kms_key.memory.arn
}
