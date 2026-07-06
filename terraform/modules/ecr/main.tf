locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "registry"
    },
    var.tags,
  )

  # Two-rule lifecycle policy:
  # Rule 1 (priority 1): untagged images expire after 7 days
  # Rule 2 (priority 2): keep at most 10 images of any status (oldest expire first)
  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ── ECR Repositories ──────────────────────────────────────────────────────────

resource "aws_ecr_repository" "service" {
  for_each = toset(var.service_names)

  name                 = "${local.name_prefix}/${each.value}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}/${each.value}"
    Service = each.value
  })
}

# ── Lifecycle Policies ────────────────────────────────────────────────────────

resource "aws_ecr_lifecycle_policy" "service" {
  for_each   = aws_ecr_repository.service
  repository = each.value.name
  policy     = local.lifecycle_policy
}
