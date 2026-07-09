output "dns_name" {
  value = aws_globalaccelerator_accelerator.this.dns_name
}

output "hosted_zone_id" {
  description = "Fixed AWS-managed hosted zone ID for the accelerator, for use in a Route 53 alias record."
  value       = aws_globalaccelerator_accelerator.this.hosted_zone_id
}

output "static_ips" {
  value = flatten([for s in aws_globalaccelerator_accelerator.this.ip_sets : s.ip_addresses])
}
