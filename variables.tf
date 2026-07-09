variable "project_name" {
  description = "Short name used as a prefix for all resource names/tags."
  type        = string
  default     = "akeyless-gateway"
}

variable "east_region" {
  description = "AWS region for the \"east\" deployment."
  type        = string
  default     = "us-east-1"
}

variable "west_region" {
  description = "AWS region for the \"west\" deployment."
  type        = string
  default     = "us-west-2"
}

variable "east_vpc_cidr" {
  description = "CIDR block for the east region VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "west_vpc_cidr" {
  description = "CIDR block for the west region VPC."
  type        = string
  default     = "10.1.0.0/16"
}

variable "instance_type" {
  description = <<-EOT
    EC2 instance type used in both regions. MicroK8s is not comfortable on
    the free-tier "micro" sizes (1 GiB RAM) once real workloads (like the
    Akeyless Gateway) are scheduled on it. Defaults to a small burstable
    instance that is NOT free-tier eligible; set to "t3.micro" or
    "t2.micro" if you want to stay within the free tier for testing and
    accept the risk of memory pressure.
  EOT
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size (GiB) for each instance."
  type        = number
  default     = 20
}

variable "key_name" {
  description = "Optional existing EC2 key pair name for SSH access. Leave null to rely on SSM Session Manager only."
  type        = string
  default     = null
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH (port 22) into the instances. Only applied when var.key_name is also set."
  type        = list(string)
  default     = []
}

variable "backend_port" {
  description = "Port on the EC2 instance that the ALB target group forwards to (e.g. the MicroK8s ingress controller's hostPort)."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "HTTP path used by ALB target group and Global Accelerator health checks."
  type        = string
  default     = "/"
}

variable "domain_name" {
  description = "Optional public domain name that the provided certificate covers. Combined with var.route53_zone_id to create a Route 53 alias record pointing it at the Global Accelerator. Purely a DNS convenience - has no effect on the certificate itself."
  type        = string
  default     = null
}

variable "route53_zone_id" {
  description = "Optional Route 53 hosted zone ID for var.domain_name, used only to create the alias record described above."
  type        = string
  default     = null
}

variable "tls_certificate_path" {
  description = "Path to the PEM-encoded Akeyless Gateway certificate to import into ACM in both regions. Required unless var.east_certificate_arn and var.west_certificate_arn are both set."
  type        = string
  default     = null
}

variable "tls_private_key_path" {
  description = "Path to the PEM-encoded private key matching var.tls_certificate_path. Required unless var.east_certificate_arn and var.west_certificate_arn are both set. NOTE: ends up in Terraform state in plaintext - use an encrypted, access-restricted backend."
  type        = string
  default     = null
}

variable "tls_certificate_chain_path" {
  description = "Optional path to a PEM-encoded certificate chain (intermediates) imported alongside the certificate."
  type        = string
  default     = null
}

variable "east_certificate_arn" {
  description = "Optional pre-existing ACM certificate ARN already present in the east region. Skips certificate import when set."
  type        = string
  default     = null
}

variable "west_certificate_arn" {
  description = "Optional pre-existing ACM certificate ARN already present in the west region. Skips certificate import when set."
  type        = string
  default     = null
}

variable "microk8s_channel" {
  description = "MicroK8s snap channel/track to install (e.g. \"1.29/stable\")."
  type        = string
  default     = "1.29/stable"
}

variable "microk8s_addons" {
  description = "MicroK8s addons to enable at boot, in addition to the base install."
  type        = list(string)
  default     = ["dns", "hostpath-storage", "ingress"]
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
