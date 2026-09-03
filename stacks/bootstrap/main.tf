module "backend" {
  source = "../../modules/terraform-backend"

  bucket_name   = var.state_bucket_name
  force_destroy = var.force_destroy
}
