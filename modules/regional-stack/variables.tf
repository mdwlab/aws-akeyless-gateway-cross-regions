variable "name_prefix" {
  description = "Prefix applied to all resource names in this region."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for this region's VPC."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the gateway host."
  type        = string
}

variable "root_volume_size" {
  description = "Root EBS volume size (GiB)."
  type        = number
}

variable "key_name" {
  description = "Optional existing EC2 key pair name for SSH access."
  type        = string
  default     = null
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH into the instance. Only applied when var.key_name is also set."
  type        = list(string)
  default     = []
}

variable "backend_port" {
  description = "Port on the EC2 instance that the ALB target group forwards to."
  type        = number
}

variable "health_check_path" {
  description = "HTTP path used by the ALB target group health check."
  type        = string
}

variable "certificate_arn" {
  description = "Optional pre-existing ACM certificate ARN already present in this region. Skips certificate import when set."
  type        = string
  default     = null
}

variable "tls_certificate_path" {
  description = "Path to the PEM-encoded certificate to import into this region's ACM. Required unless var.certificate_arn is set."
  type        = string
  default     = null
}

variable "tls_private_key_path" {
  description = "Path to the PEM-encoded private key matching var.tls_certificate_path. Required unless var.certificate_arn is set."
  type        = string
  default     = null
}

variable "tls_certificate_chain_path" {
  description = "Optional path to a PEM-encoded certificate chain (intermediates) to import alongside the certificate."
  type        = string
  default     = null
}

variable "microk8s_channel" {
  description = "MicroK8s snap channel/track to install."
  type        = string
}

variable "microk8s_addons" {
  description = "MicroK8s addons to enable at boot."
  type        = list(string)
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
