# Optional convenience: point var.domain_name at the Global Accelerator via
# a Route 53 alias record. Has no bearing on the imported TLS certificate -
# that must already cover this domain name on its own.
resource "aws_route53_record" "accelerator_alias" {
  count    = var.domain_name != null && var.route53_zone_id != null ? 1 : 0
  provider = aws.east

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.global_accelerator.dns_name
    zone_id                = module.global_accelerator.hosted_zone_id
    evaluate_target_health = false
  }
}
