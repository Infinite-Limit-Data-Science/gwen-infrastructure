output "runtime_id" {
  value = var.deploy_runtime ? aws_bedrockagentcore_agent_runtime.this[0].agent_runtime_id : null
}

output "runtime_arn" {
  value = var.deploy_runtime ? aws_bedrockagentcore_agent_runtime.this[0].agent_runtime_arn : null
}

output "endpoint" {
  value = local.endpoint
}

output "role_name" {
  value = aws_iam_role.runtime.name
}

output "role_arn" {
  value = aws_iam_role.runtime.arn
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.runtime.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.runtime.repository_url
}
