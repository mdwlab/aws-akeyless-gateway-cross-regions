module "east" {
  source = "./modules/regional-stack"

  providers = {
    aws = aws.east
  }

  name_prefix                = "${var.project_name}-east"
  vpc_cidr                   = var.east_vpc_cidr
  instance_type              = var.instance_type
  root_volume_size           = var.root_volume_size
  key_name                   = var.key_name
  allowed_ssh_cidr_blocks    = var.allowed_ssh_cidr_blocks
  backend_port               = var.backend_port
  health_check_path          = var.health_check_path
  certificate_arn            = var.east_certificate_arn
  tls_certificate_path       = var.tls_certificate_path
  tls_private_key_path       = var.tls_private_key_path
  tls_certificate_chain_path = var.tls_certificate_chain_path
  microk8s_channel           = var.microk8s_channel
  microk8s_addons            = var.microk8s_addons
  tags                       = var.tags
}

module "west" {
  source = "./modules/regional-stack"

  providers = {
    aws = aws.west
  }

  name_prefix                = "${var.project_name}-west"
  vpc_cidr                   = var.west_vpc_cidr
  instance_type              = var.instance_type
  root_volume_size           = var.root_volume_size
  key_name                   = var.key_name
  allowed_ssh_cidr_blocks    = var.allowed_ssh_cidr_blocks
  backend_port               = var.backend_port
  health_check_path          = var.health_check_path
  certificate_arn            = var.west_certificate_arn
  tls_certificate_path       = var.tls_certificate_path
  tls_private_key_path       = var.tls_private_key_path
  tls_certificate_chain_path = var.tls_certificate_chain_path
  microk8s_channel           = var.microk8s_channel
  microk8s_addons            = var.microk8s_addons
  tags                       = var.tags
}

# Global Accelerator is a global service, but the Terraform resources still
# need a "home" provider to call the API through. Any region works; we reuse
# the east provider rather than adding a third provider alias.
module "global_accelerator" {
  source = "./modules/global-accelerator"

  providers = {
    aws = aws.east
  }

  name_prefix       = var.project_name
  east_region       = var.east_region
  west_region       = var.west_region
  east_alb_arn      = module.east.alb_arn
  west_alb_arn      = module.west.alb_arn
  health_check_path = var.health_check_path
  tags              = var.tags
}
