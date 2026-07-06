locals {
  name_prefix = "${var.project}-${var.environment}"

  # Tech spec: dev → petclinic-dev.{domain}, prod → petclinic.{domain}
  app_subdomain = var.environment == "dev" ? "petclinic-dev" : "petclinic"
  app_fqdn      = "${local.app_subdomain}.${var.domain_name}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "dns"
    },
    var.tags,
  )
}

# ── Route 53 Hosted Zone ──────────────────────────────────────────────────────

resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-zone"
  })
}

# ── ACM Wildcard Certificate (PETPLAT-28) ─────────────────────────────────────
# Wildcard covers all subdomains: petclinic-dev.{domain}, petclinic.{domain}, etc.
# DNS validation is fully automated via the Route 53 CNAME records below.

resource "aws_acm_certificate" "main" {
  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ── ACM DNS Validation Records ────────────────────────────────────────────────

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ── Route 53 A Record → ALB (PETPLAT-31) ─────────────────────────────────────
# Two-phase deployment: apply DNS module first (Phase 1), deploy K8s Ingress
# so the ALB is created, then re-apply with alb_dns_name set (Phase 2).
#
# Phase 1: terraform apply -var domain_name=example.com
# Phase 2: terraform apply -var domain_name=example.com \
#            -var alb_dns_name=$(kubectl get ingress api-gateway -n petclinic-dev \
#                                  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

resource "aws_route53_record" "app" {
  count = var.alb_dns_name != "" ? 1 : 0

  zone_id = aws_route53_zone.main.zone_id
  name    = local.app_fqdn
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_hosted_zone_id
    evaluate_target_health = true
  }
}
