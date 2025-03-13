output "alb_dns_name" {
  value = aws_lb.alb.dns_name
  description = "The DNS name of the Application Load Balancer"
}