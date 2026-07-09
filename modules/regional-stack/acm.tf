# Certificate lifecycle:
#   1. var.certificate_arn set -> use an existing, already-in-ACM certificate directly.
#   2. var.certificate_arn null -> import the PEM certificate/key provided via
#      var.tls_certificate_path / var.tls_private_key_path into this region's ACM.
#      ACM certificates are regional, so the same PEM material gets imported
#      separately into each region.
#
# NOTE: the imported private key ends up in Terraform state in plaintext
# (ACM's "sensitive" schema flag only redacts CLI output, not state).
# Protect state accordingly - encrypted remote backend, restricted access.

resource "aws_acm_certificate" "imported" {
  count = var.certificate_arn == null ? 1 : 0

  private_key       = file(var.tls_private_key_path)
  certificate_body  = file(var.tls_certificate_path)
  certificate_chain = var.tls_certificate_chain_path != null ? file(var.tls_certificate_chain_path) : null

  tags = merge(var.tags, { Name = "${var.name_prefix}-cert" })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  certificate_arn = coalesce(var.certificate_arn, try(aws_acm_certificate.imported[0].arn, null))
}
