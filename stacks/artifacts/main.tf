module "artifacts" {
  source = "../../modules/artifact-store"

  environment      = var.environment
  parameter_prefix = "/gwen/${var.environment}/platform/artifacts"
  retention_days   = var.retention_days
  force_destroy    = var.force_destroy
}
