output "east_alb_dns_name" {
  description = "DNS name of the east region ALB."
  value       = module.east.alb_dns_name
}

output "west_alb_dns_name" {
  description = "DNS name of the west region ALB."
  value       = module.west.alb_dns_name
}

output "east_instance_public_ip" {
  description = "Public IP of the east region EC2 instance."
  value       = module.east.instance_public_ip
}

output "west_instance_public_ip" {
  description = "Public IP of the west region EC2 instance."
  value       = module.west.instance_public_ip
}

output "east_certificate_arn" {
  description = "ACM certificate ARN in use in the east region (imported or bring-your-own)."
  value       = module.east.certificate_arn
}

output "west_certificate_arn" {
  description = "ACM certificate ARN in use in the west region (imported or bring-your-own)."
  value       = module.west.certificate_arn
}

output "global_accelerator_dns_name" {
  description = "DNS name of the Global Accelerator. Point var.domain_name at this (e.g. via a CNAME/ALIAS record)."
  value       = module.global_accelerator.dns_name
}

output "global_accelerator_static_ips" {
  description = "The two static anycast IPs assigned to the Global Accelerator."
  value       = module.global_accelerator.static_ips
}
