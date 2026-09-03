module "memory" {
  source = "../../modules/agentcore-memory"

  environment       = var.environment
  name              = "gwen_primary_memory_${var.environment}"
  parameter_prefix  = "/gwen/${var.environment}/platform/memory"
  event_expiry_days = var.event_expiry_days
  enable_episodic   = var.enable_episodic
}
