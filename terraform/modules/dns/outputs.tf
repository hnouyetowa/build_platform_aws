output "zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "name_servers" {
  description = "NS records to delegate from your registrar to Route 53"
  value       = aws_route53_zone.main.name_servers
}

output "certificate_arn" {
  description = "ACM wildcard certificate ARN — use in ALB Ingress annotation"
  value       = aws_acm_certificate_validation.main.certificate_arn
}

output "app_fqdn" {
  description = "Fully-qualified domain name for this environment's app endpoint"
  value       = local.app_fqdn
}

output "app_url" {
  description = "HTTPS URL for the Petclinic application in this environment"
  value       = "https://${local.app_fqdn}"
}
