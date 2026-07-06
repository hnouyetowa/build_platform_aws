locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "karpenter"
    },
    var.tags,
  )
}

data "aws_caller_identity" "current" {}

# ── Karpenter Controller IRSA Role ────────────────────────────────────────────
# Trust policy uses EKS OIDC outputs — never hardcoded.

data "aws_iam_policy_document" "karpenter_assume_role" {
  statement {
    sid     = "KarpenterOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter" {
  name               = "${local.name_prefix}-karpenter-role"
  description        = "IRSA role for Karpenter controller in ${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.karpenter_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-karpenter-role"
  })
}

# ── Karpenter IAM Policy — least privilege ────────────────────────────────────

data "aws_iam_policy_document" "karpenter" {
  # EC2 Fleet API — needed to provision nodes
  statement {
    sid    = "EC2NodeProvisioning"
    effect = "Allow"
    actions = [
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateTags",
      "ec2:DeleteLaunchTemplate",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # EC2 Describe — read-only, cannot be scoped to specific resources
  statement {
    sid    = "EC2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]
  }

  # PassRole restricted to the EKS node role only (enforcement rule)
  statement {
    sid     = "PassRoleToNodes"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [var.node_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # SSM — read AMI parameters for AL2023
  statement {
    sid    = "SSMGetParameter"
    effect = "Allow"
    actions = ["ssm:GetParameter"]
    resources = [
      "arn:aws:ssm:${var.region}::parameter/aws/service/*",
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/karpenter/*",
    ]
  }

  # Pricing — needed for Spot instance selection
  statement {
    sid       = "Pricing"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  # SQS — read Spot interruption events from queue
  statement {
    sid    = "SQSInterruption"
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.interruption.arn]
  }

  # EKS — discover cluster configuration
  statement {
    sid    = "EKSCluster"
    effect = "Allow"
    actions = ["eks:DescribeCluster"]
    resources = [
      "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}",
    ]
  }
}

resource "aws_iam_policy" "karpenter" {
  name        = "${local.name_prefix}-karpenter-policy"
  description = "Least-privilege policy for Karpenter controller in ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.karpenter.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-karpenter-policy"
  })
}

resource "aws_iam_role_policy_attachment" "karpenter" {
  role       = aws_iam_role.karpenter.name
  policy_arn = aws_iam_policy.karpenter.arn
}

# ── SQS Interruption Queue ────────────────────────────────────────────────────
# Receives Spot interruption, rebalance, state change, and health events.

resource "aws_sqs_queue" "interruption" {
  name                      = "${local.name_prefix}-karpenter-interruption"
  message_retention_seconds = 300   # 5 minutes — events are processed quickly
  sqs_managed_sse_enabled   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-karpenter-interruption"
  })
}

# Queue policy — allows EventBridge to publish messages (enforcement rule)
data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid    = "EventBridgePutMessage"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values = [
        aws_cloudwatch_event_rule.spot_interruption.arn,
        aws_cloudwatch_event_rule.rebalance.arn,
        aws_cloudwatch_event_rule.instance_state_change.arn,
        aws_cloudwatch_event_rule.scheduled_change.arn,
      ]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy    = data.aws_iam_policy_document.interruption_queue.json
}

# ── EventBridge Rules ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${local.name_prefix}-karpenter-spot-interruption"
  description = "Route EC2 Spot Interruption Warnings to Karpenter SQS queue"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-karpenter-spot-interruption"
  })
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "KarpenterSQS"
  arn       = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_rule" "rebalance" {
  name        = "${local.name_prefix}-karpenter-rebalance"
  description = "Route EC2 Instance Rebalance Recommendations to Karpenter SQS queue"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-karpenter-rebalance"
  })
}

resource "aws_cloudwatch_event_target" "rebalance" {
  rule      = aws_cloudwatch_event_rule.rebalance.name
  target_id = "KarpenterSQS"
  arn       = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name        = "${local.name_prefix}-karpenter-instance-state-change"
  description = "Route EC2 Instance State Change events to Karpenter SQS queue"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-karpenter-instance-state-change"
  })
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule      = aws_cloudwatch_event_rule.instance_state_change.name
  target_id = "KarpenterSQS"
  arn       = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_rule" "scheduled_change" {
  name        = "${local.name_prefix}-karpenter-scheduled-change"
  description = "Route AWS Health scheduled change events to Karpenter SQS queue"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-karpenter-scheduled-change"
  })
}

resource "aws_cloudwatch_event_target" "scheduled_change" {
  rule      = aws_cloudwatch_event_rule.scheduled_change.name
  target_id = "KarpenterSQS"
  arn       = aws_sqs_queue.interruption.arn
}

# ── Node Instance Profile ─────────────────────────────────────────────────────
# Name MUST match the EC2NodeClass instanceProfile reference in Kubernetes.
# Format: petclinic-{env}-karpenter-node-profile

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${local.name_prefix}-karpenter-node-profile"
  role = var.node_role_name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-karpenter-node-profile"
  })
}
