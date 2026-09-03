output "id" {
  value = aws_bedrockagentcore_memory.this.id
}

output "arn" {
  value = aws_bedrockagentcore_memory.this.arn
}

output "kms_key_arn" {
  value = aws_kms_key.memory.arn
}
