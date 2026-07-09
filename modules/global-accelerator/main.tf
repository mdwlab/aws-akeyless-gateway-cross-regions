resource "aws_globalaccelerator_accelerator" "this" {
  name            = "${var.name_prefix}-ga"
  ip_address_type = "IPV4"
  enabled         = true

  tags = var.tags
}

resource "aws_globalaccelerator_listener" "this" {
  accelerator_arn = aws_globalaccelerator_accelerator.this.id
  client_affinity = "NONE"
  protocol        = "TCP"

  port_range {
    from_port = 443
    to_port   = 443
  }
}

resource "aws_globalaccelerator_endpoint_group" "east" {
  listener_arn          = aws_globalaccelerator_listener.this.id
  endpoint_group_region = var.east_region

  endpoint_configuration {
    endpoint_id = var.east_alb_arn
    weight      = 100
  }

  health_check_protocol   = "HTTPS"
  health_check_port       = 443
  health_check_path       = var.health_check_path
  traffic_dial_percentage = 100
}

resource "aws_globalaccelerator_endpoint_group" "west" {
  listener_arn          = aws_globalaccelerator_listener.this.id
  endpoint_group_region = var.west_region

  endpoint_configuration {
    endpoint_id = var.west_alb_arn
    weight      = 100
  }

  health_check_protocol   = "HTTPS"
  health_check_port       = 443
  health_check_path       = var.health_check_path
  traffic_dial_percentage = 100
}
