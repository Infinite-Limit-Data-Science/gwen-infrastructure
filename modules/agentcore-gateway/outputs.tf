output "id" {
  value = aws_bedrockagentcore_gateway.this.gateway_id
}

output "arn" {
  value = aws_bedrockagentcore_gateway.this.gateway_arn
}

output "url" {
  value = aws_bedrockagentcore_gateway.this.gateway_url
}

output "role_name" {
  value = aws_iam_role.gateway.name
}

output "role_arn" {
  value = aws_iam_role.gateway.arn
}

output "policy_engine_id" {
  value = aws_bedrockagentcore_policy_engine.this.policy_engine_id
}

output "policy_engine_arn" {
  value = aws_bedrockagentcore_policy_engine.this.policy_engine_arn
}
