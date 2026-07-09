# aws-ec2-gateway-cross-regions

Terraform to stand up the AWS infrastructure for a cross-region Akeyless
Gateway deployment: one EC2 instance per region running MicroK8s, fronted by
regional Application Load Balancers, tied together with AWS Global
Accelerator for a single global entry point.

This repo only generates/manages the AWS infrastructure. It does **not**
install the Akeyless Gateway itself - that's done by hand inside each
MicroK8s cluster after the instances come up.

## Architecture

```
                      Global Accelerator (anycast, TCP:443)
                       /                              \
              endpoint group (us-east-1)      endpoint group (us-west-2)
                       |                              |
                  ALB (HTTPS:443)                ALB (HTTPS:443)
                  TLS terminated here             TLS terminated here
                       |                              |
              target group -> EC2:80           target group -> EC2:80
                       |                              |
              VPC (10.0.0.0/16)                VPC (10.1.0.0/16)
              2 public subnets                 2 public subnets
              EC2 (Ubuntu 24.04 LTS)            EC2 (Ubuntu 24.04 LTS)
              MicroK8s installed via            MicroK8s installed via
              cloud-init at boot                cloud-init at boot
```

- **Global Accelerator** is the single public entry point. It health-checks
  both regional ALBs and routes client traffic to whichever is healthy/closer.
- **ALB terminates TLS** (per-region, using the certificate imported into
  that region's ACM) and forwards plain HTTP inside the VPC to the instance's
  MicroK8s ingress.
- **EC2** instances sit in public subnets (no NAT gateway, to avoid its
  hourly cost); their security group only accepts backend traffic from the
  ALB's security group, plus optional SSH from CIDRs you specify. Management
  access is otherwise via **SSM Session Manager** (the instance role attaches
  `AmazonSSMManagedInstanceCore`), so no SSH key is required by default.
- **MicroK8s** is installed via a cloud-init script passed as EC2
  `user_data`. This is the extent to which Terraform can "install" it -
  Terraform provisions the instance and hands off a boot-time script; it
  does not manage in-cluster state. Installing the Akeyless Gateway into
  the running cluster is a separate, manual step.

## Repo layout

```
.
├── main.tf, variables.tf, outputs.tf, providers.tf, versions.tf, dns.tf
├── terraform.tfvars.example
└── modules/
    ├── regional-stack/     # everything for one region: VPC, subnets, IGW,
    │                       # route table, security groups, IAM role/instance
    │                       # profile, EC2 instance + cloud-init, ACM cert,
    │                       # ALB + target group + listeners
    └── global-accelerator/ # the accelerator, listener, and one endpoint
                             # group per region
```

The root module instantiates `regional-stack` twice - once per region, each
via a differently-aliased AWS provider (`aws.east` / `aws.west`) passed in
through the module's `providers` block. There is intentionally no default
(unaliased) `aws` provider; every resource is created through an explicit
alias.

## Usage

```
terraform init
terraform fmt -recursive
terraform validate
terraform plan          # review the plan
# terraform apply is a deliberate, separate step - not run for you
```

Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in values
before planning. At minimum you need to point `tls_certificate_path` /
`tls_private_key_path` at the Akeyless Gateway's PEM certificate and key (or
supply `east_certificate_arn` / `west_certificate_arn` if you've already
imported a certificate into ACM in both regions yourself).

### Staged rollout (optional)

Terraform's dependency graph already applies things in the right order (and
parallelizes across `east`/`west`) within a single `terraform apply`. For a
POC, though, it can be worth applying in explicit layers with `-target` so
you can check each one (VPC in the console, EC2/MicroK8s health,
ALB target health, ...) before moving on:

1. **Networking** - `-target=module.east.aws_route_table_association.public`
   (+ `module.west...`) pulls in the subnets, route table, IGW, and VPC as
   dependencies.
2. **Security groups** - `-target=module.east.aws_security_group.ec2`
   (+ `module.west...`) pulls in the ALB security group too.
3. **IAM** - `-target=module.east.aws_iam_instance_profile.gateway`
   (+ `module.west...`).
4. **ACM certificate import** -
   `-target=module.east.aws_acm_certificate.imported[0]` (+ `module.west...`).
5. **EC2 instance** - `-target=module.east.aws_instance.gateway`
   (+ `module.west...`) - this is where the MicroK8s cloud-init kicks off.
6. **ALB** -
   `-target=module.east.aws_lb_listener.https`,
   `aws_lb_listener.http_redirect`, `aws_lb_target_group_attachment.this`
   (+ `module.west...` equivalents).
7. **Global Accelerator** - `-target=module.global_accelerator` (requires
   both regions' ALBs to already exist, since it reads their ARNs).
8. **Route 53 alias** (optional) -
   `-target=aws_route53_record.accelerator_alias[0]`.

Always finish with a plain, untargeted `terraform apply` - HashiCorp
documents `-target` as a troubleshooting/staging aid, not a routine
workflow, since a targeted apply only pulls in a resource's *dependencies*,
never things that depend on it. The final untargeted apply reconciles state
with the full configuration and should show "no changes" if the staged
rollout went cleanly.

### TLS certificate handling

ACM certificates are regional, so the same PEM material gets imported
separately into ACM in `us-east-1` and `us-west-2`. This is a plain ACM
*import* (`aws_acm_certificate` with `private_key`/`certificate_body`), not
an Amazon-issued/DNS-validated certificate - there's no domain validation
step to wait on.

**Security note:** the private key ends up in Terraform state in plaintext.
ACM's "sensitive" flag on that attribute only redacts it from CLI/plan
output, not from the state file itself. Use a remote backend with encryption
at rest and tightly restricted access, and treat the state file as secret
material.

If you'd rather the private key never touch Terraform state at all,
terminate TLS at the MicroK8s ingress instead and change the ALB listener to
TCP passthrough - that's a bigger change to `modules/regional-stack/alb.tf`
and not what's implemented here, since ALB termination was the stated
preference.

### Backend port / health checks

`var.backend_port` (default `80`) is the port the ALB target group forwards
to on the instance - wire it up to whatever the MicroK8s ingress controller
listens on once you've deployed the Akeyless Gateway's ingress. Same for
`var.health_check_path`, used by both the ALB target group and the Global
Accelerator endpoint group health checks.

## Cost notes

This is **not** a free deployment, even though EC2 itself can be:

- **EC2**: `t2.micro`/`t3.micro` are free-tier eligible (750 instance-hours/
  month combined, for 12 months on new accounts), but 1 GiB of RAM is tight
  for MicroK8s plus a real workload. The default here is `t3.medium` (not
  free tier) precisely to avoid that memory pressure; override
  `instance_type` if you want to test on the free tier and accept the risk.
- **EBS**: default 20 GiB root volume per instance (40 GiB total across both
  regions) is within the 30 GiB/region free-tier allowance, but close to it
  if you also run other EBS volumes in the same account/region.
- **ALB** (one per region, so ×2 here): a fixed **hourly charge per ALB**
  (~$16-20/month each) that accrues whether or not it serves any traffic,
  plus **LCU-hours** billed on whichever is highest each hour of new
  connections/sec, active connections/min, processed bytes/hour, or rule
  evaluations/sec. At POC traffic levels the LCU portion is typically small;
  the hourly charge is not.
- **Global Accelerator** (one, shared across both regions): a fixed
  **hourly accelerator fee** (~$18/month) that accrues regardless of
  traffic, plus a **per-GB data transfer premium** for traffic through its
  edge network (roughly $0.015-$0.05+/GB depending on client-to-region
  path) - this is *on top of*, not instead of, normal AWS data-transfer-out
  charges.
- None of the above is covered by the free tier. Even fully idle, 2× ALB +
  1× GA hourly fees put a floor of roughly **$50-60/month** on this
  architecture before any real traffic - and since that floor is
  time-based rather than traffic-based, `terraform destroy` between test
  sessions (rather than leaving it running 24/7) is the main lever for
  cutting cost on a POC. Treat these numbers as ballpark/region-dependent;
  check the AWS Pricing Calculator for current figures.

## Next steps (not automated here)

1. `terraform apply` this configuration once you've reviewed the plan.
2. On each instance, confirm MicroK8s is healthy (`microk8s status`, see
   `/var/log/microk8s-install.log` / `/var/log/microk8s-install-complete` for
   cloud-init progress).
3. Install the Akeyless Gateway into each MicroK8s cluster by hand, and
   expose it via an ingress on `var.backend_port`.
