module "observability" {
  source = "../../modules/observability"

  environment      = var.environment
  retention_days   = var.retention_days
  parameter_prefix = "/gwen/${var.environment}/platform/observability"
}
