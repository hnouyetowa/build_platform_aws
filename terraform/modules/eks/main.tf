locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "compute"
    },
    var.tags,
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Cluster IAM Role ──────────────────────────────────────────────────────────

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_eks_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = local.name_prefix
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [var.cluster_sg_id]
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })

  depends_on = [aws_iam_role_policy_attachment.cluster_eks_policy]
}

# ── OIDC Provider ─────────────────────────────────────────────────────────────

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-oidc-provider"
  })
}

locals {
  oidc_provider_id    = replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")
  admin_principal_arn = var.admin_iam_principal_arn != "" ? var.admin_iam_principal_arn : data.aws_caller_identity.current.arn
}

# ── Node IAM Role ─────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── Launch Template ───────────────────────────────────────────────────────────
# When a launch template specifies security groups, EKS will not add the
# cluster security group automatically — so both SGs are included explicitly:
# - var.node_sg_id: our custom SG (controls RDS access, ALB NodePort rules)
# - cluster_security_group_id: EKS-managed SG (required for control-plane ↔ node comms)

resource "aws_launch_template" "node" {
  name_prefix = "${local.name_prefix}-node-"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  vpc_security_group_ids = [
    var.node_sg_id,
    aws_eks_cluster.main.vpc_config[0].cluster_security_group_id,
  ]

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-node"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-node-volume"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-node-lt"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ── Managed Node Group ────────────────────────────────────────────────────────

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.node_instance_types
  ami_type       = var.node_ami_type
  capacity_type  = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nodes"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
  ]

  # Karpenter or manual scaling may adjust desired_size — prevent Terraform drift
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ── kubectl Access Entry ──────────────────────────────────────────────────────

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = local.admin_principal_arn
  type          = "STANDARD"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-admin-access-entry"
  })
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# ── EBS CSI Driver IRSA Role (required for Prometheus/Grafana PersistentVolumes) ─

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_id}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_id}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ebs-csi-role"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ── AWS Load Balancer Controller IRSA Role (PETPLAT-29) ──────────────────────
# IRSA scoped to the aws-load-balancer-controller ServiceAccount in kube-system.
# The custom IAM policy grants the controller the permissions it needs to
# create/manage ALBs, target groups, listeners, and SGs on behalf of Ingress objects.

data "aws_iam_policy_document" "lb_controller_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_id}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_id}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${local.name_prefix}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lb-controller-role"
  })
}

data "aws_iam_policy_document" "lb_controller" {
  statement {
    sid     = "CreateServiceLinkedRole"
    effect  = "Allow"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::*:role/aws-service-role/elasticloadbalancing.amazonaws.com/AWSServiceRoleForElasticLoadBalancing"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  # EC2 Describe* actions cannot be scoped to specific resources by IAM design
  # (they operate at the account/region level, not per-resource ARN).
  # This is unavoidable and consistent with the official AWS LB Controller policy.
  statement {
    sid    = "DescribeEC2Resources"
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeCoipPools",
      "ec2:DescribeInstances",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcs",
      "ec2:GetCoipPoolUsage",
    ]
    resources = ["*"]
  }

  # SG management restricted to security groups tagged with the cluster name.
  # The controller tags SGs it creates with elbv2.k8s.aws/cluster=<cluster-name>.
  statement {
    sid    = "ManageSecurityGroups"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:RevokeSecurityGroupIngress",
    ]
    resources = ["arn:aws:ec2:*:*:security-group/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = [local.name_prefix]
    }
  }

  statement {
    sid    = "CreateSecurityGroupUntagged"
    effect = "Allow"
    actions = ["ec2:CreateSecurityGroup"]
    resources = ["arn:aws:ec2:*:*:vpc/*"]
  }

  statement {
    sid    = "TagSecurityGroups"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["arn:aws:ec2:*:*:security-group/*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSecurityGroup"]
    }
  }

  # ModifyNetworkInterfaceAttribute restricted to ENIs tagged by the cluster.
  statement {
    sid    = "ManageNetworkInterfaces"
    effect = "Allow"
    actions = ["ec2:ModifyNetworkInterfaceAttribute"]
    resources = ["arn:aws:ec2:*:*:network-interface/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = [local.name_prefix]
    }
  }

  # ELB Describe* also cannot be scoped to specific resources by IAM design.
  statement {
    sid    = "ELBDescribe"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTrustStores",
    ]
    resources = ["*"]
  }

  # ELB create/modify/delete restricted to resources tagged with this cluster.
  statement {
    sid    = "ELBManageTagged"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = [local.name_prefix]
    }
  }

  statement {
    sid    = "ELBTagExistingResources"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = [local.name_prefix]
    }
  }

  # ACM/IAM certificate read access — Describe* cannot be scoped by resource.
  statement {
    sid    = "CertificateAccess"
    effect = "Allow"
    actions = [
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "iam:GetServerCertificate",
      "iam:ListServerCertificates",
    ]
    resources = ["*"]
  }
  # Cognito, WAF, and Shield permissions are intentionally excluded:
  # - This project does not use Cognito-based ALB authentication
  # - WAF integration is not configured
  # - Shield Advanced is not subscribed
  # Add them here if those features are enabled in the future.
}

resource "aws_iam_policy" "lb_controller" {
  name        = "${local.name_prefix}-lb-controller-policy"
  description = "IAM policy for the AWS Load Balancer Controller running in ${local.name_prefix}"
  policy      = data.aws_iam_policy_document.lb_controller.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lb-controller-policy"
  })
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

# ── EKS Managed Add-ons ───────────────────────────────────────────────────────
# Versions resolved at apply time to the cluster default (not latest) to
# ensure deliberate upgrades rather than automatic version changes.

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = false
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = false
}

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = false
}

data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = false
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-addon-coredns"
  })

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = data.aws_eks_addon_version.kube_proxy.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-addon-kube-proxy"
  })

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.vpc_cni.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-addon-vpc-cni"
  })

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.ebs_csi.version
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-addon-ebs-csi"
  })

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.ebs_csi_policy,
  ]
}
