# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project purpose

Terraform that provisions the AWS infrastructure for a cross-region Akeyless
Gateway deployment: one EC2 instance per region (MicroK8s installed via
cloud-init), each behind a regional ALB that terminates TLS, all tied
together by a single AWS Global Accelerator. See `README.md` for the full
architecture diagram, cost notes, and TLS certificate handling.

This repo generates AWS infrastructure only. It does not install or manage
the Akeyless Gateway itself (that happens by hand inside each MicroK8s
cluster after `apply`), and there is no application code, build, or test
suite here - only Terraform.

## Commands

```
terraform init
terraform fmt -recursive     # formats all root + module files
terraform validate           # syntax/type check, no AWS calls, safe to run anytime
terraform plan               # requires AWS credentials + terraform.tfvars
terraform apply               # NEVER run this unless the user explicitly asks -
                               # this repo is treated as codegen, not a live deployment
```

`terraform init -backend=false` + `terraform validate` is enough to check
that edits are syntactically/structurally correct without needing AWS
credentials or a backend configured - use that as the default sanity check
after making changes, rather than `plan`.

There's no single-module `plan`/`apply` shortcut - `-target` works if you
need to scope to `module.east`, `module.west`, or `module.global_accelerator`
individually.

## Architecture

- **`providers.tf`** defines two aliased providers, `aws.east` and
  `aws.west`, and deliberately no default (unaliased) `aws` provider. Every
  resource is created by a child module that receives one of these aliases
  through its `providers = { aws = aws.east }` block. Any new root-level
  resource (like `dns.tf`'s Route 53 record) must set `provider = aws.east`
  (or `.west`) explicitly, or it will fail with a missing-provider error.
- **`modules/regional-stack`** is instantiated once per region from root
  `main.tf`. It owns everything scoped to one region: VPC, 2 public subnets
  (no NAT gateway - EC2 sits in the public subnet directly, security-group
  restricted to ALB-sourced traffic), IAM role/instance profile (SSM Session
  Manager access, no SSH key required by default), the EC2 instance +
  cloud-init MicroK8s bootstrap, the ACM certificate, and the ALB + target
  group + listeners.
- **`modules/global-accelerator`** is instantiated once from root and takes
  both regions' ALB ARNs as input, creating one endpoint group per region.
  Global Accelerator is a global service but the Terraform resources still
  need a "home" provider to call through - root reuses `aws.east` for this
  rather than adding a third alias.
- **TLS certificates are imported, not issued.** `modules/regional-stack/acm.tf`
  expects PEM certificate/key material (the Akeyless Gateway's own cert) and
  imports it into ACM per-region via `aws_acm_certificate.imported`
  (`private_key`/`certificate_body`/`certificate_chain`), since ACM certs are
  regional and the same material must exist in both. There is no
  DNS-validation flow in this repo - if you're tempted to add
  Amazon-issued/DNS-validated certs, that's a different code path
  (`validation_method = "DNS"` + `aws_acm_certificate_validation`) and
  should probably be a separate opt-in variable, not a replacement for the
  import path other code depends on (`local.certificate_arn` in
  `acm.tf` is what `alb.tf`'s HTTPS listener consumes).
- **MicroK8s installation is a boot-time cloud-init script**
  (`modules/regional-stack/templates/install-microk8s.sh.tpl`), rendered via
  `templatefile()` into the EC2 instance's `user_data`. This is the ceiling
  of what Terraform can do here - it can bootstrap the snap install and
  enable addons on first boot, but has no ongoing management of in-cluster
  state. `user_data_replace_on_change = true` means editing the template or
  its variables (`microk8s_channel`, `microk8s_addons`) forces instance
  replacement, not an in-place re-run.
- **Backend port**: `var.backend_port` (default `80`) is what the ALB
  target group forwards to on the instance - it's meant to line up with
  whatever the MicroK8s ingress controller listens on once the Akeyless
  Gateway is deployed. It has no default binding to any specific ingress
  today; changing it doesn't reconfigure anything inside the cluster.
