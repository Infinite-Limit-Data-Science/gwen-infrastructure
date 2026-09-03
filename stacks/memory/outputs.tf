output "memory" {
  value = {
    id          = module.memory.id
    arn         = module.memory.arn
    kms_key_arn = module.memory.kms_key_arn
  }
}
