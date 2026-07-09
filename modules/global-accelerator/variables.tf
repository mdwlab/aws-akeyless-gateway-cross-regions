variable "name_prefix" {
  description = "Prefix applied to the accelerator's name."
  type        = string
}

variable "east_region" {
  description = "Region of the east ALB endpoint."
  type        = string
}

variable "west_region" {
  description = "Region of the west ALB endpoint."
  type        = string
}

variable "east_alb_arn" {
  description = "ARN of the east region ALB to register as an endpoint."
  type        = string
}

variable "west_alb_arn" {
  description = "ARN of the west region ALB to register as an endpoint."
  type        = string
}

variable "health_check_path" {
  description = "HTTP(S) path Global Accelerator uses to health-check each endpoint (the ALB)."
  type        = string
}

variable "tags" {
  description = "Common tags applied to the accelerator."
  type        = map(string)
  default     = {}
}
