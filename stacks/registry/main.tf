module "registry" {
  source = "../../modules/agentcore-registry"

  name               = coalesce(var.registry_name, "gwen-specialists-${var.tenant_slug}-${var.environment}")
  environment        = var.environment
  aws_region         = var.aws_region
  aws_profile        = var.aws_profile
  parameter_name     = "/gwen/${var.environment}/platform/registries/${var.tenant_slug}/id"
  reconcile_revision = var.reconcile_revision
}
