resource "terraform_data" "registry" {
  input = {
    description = var.description
    environment = var.environment
    name        = var.name
    revision    = var.reconcile_revision
  }

  provisioner "local-exec" {
    command = "python3 ${path.module}/scripts/reconcile_registry.py --region '${var.aws_region}' --profile '${var.aws_profile}' --name '${var.name}' --description '${var.description}' --environment '${var.environment}' --parameter-name '${var.parameter_name}'"
  }
}

data "aws_ssm_parameter" "registry_id" {
  name       = var.parameter_name
  depends_on = [terraform_data.registry]
}
