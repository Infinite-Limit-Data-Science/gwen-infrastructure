output "gateway" {
  value = {
    id               = module.gateway.id
    arn              = module.gateway.arn
    url              = module.gateway.url
    role_name        = module.gateway.role_name
    role_arn         = module.gateway.role_arn
    policy_engine_id = module.gateway.policy_engine_id
  }
}
