output "vpc_id" {
  value = aws_vpc.this.id
}

output "instance_id" {
  value = aws_instance.gateway.id
}

output "instance_public_ip" {
  value = aws_instance.gateway.public_ip
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "certificate_arn" {
  value = local.certificate_arn
}
