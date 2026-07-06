locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "networking"
    },
    var.tags,
  )
}

# ── VPC ────────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# ── Public Subnets ─────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch             = true
  assign_ipv6_address_on_creation     = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
    # Required for EKS subnet discovery and ALB provisioning
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  })
}

# ── Internet Gateway ──────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# ── Route Table ───────────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Security Groups ───────────────────────────────────────────────────────────
# All SGs are created without inline rules to avoid circular dependency issues
# (EKS cluster SG ↔ EKS node SG reference each other). Rules are added
# below using aws_vpc_security_group_*_rule resources.

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "Control plane security group for EKS cluster ${local.name_prefix}"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "eks_node" {
  name        = "${local.name_prefix}-node-sg"
  description = "Worker node security group for EKS cluster ${local.name_prefix}"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-node-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Security group for RDS MySQL — allows 3306 from EKS nodes only"
  vpc_id      = aws_vpc.main.id
  # AWS creates a default allow-all egress rule when no egress blocks are defined.
  # This is intentional: RDS is a stateful managed service that only responds to
  # inbound connections initiated by EKS nodes — it does not initiate outbound
  # connections. Return traffic is automatically allowed by stateful SG tracking.

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-rds-sg"
    Component = "database"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for internet-facing ALB — HTTP/HTTPS from anywhere"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ── EKS Cluster SG Rules ──────────────────────────────────────────────────────

resource "aws_vpc_security_group_ingress_rule" "eks_cluster_from_nodes_443" {
  security_group_id            = aws_security_group.eks_cluster.id
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from EKS worker nodes to API server"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-from-nodes-443"
  })
}

resource "aws_vpc_security_group_egress_rule" "eks_cluster_all_outbound" {
  security_group_id = aws_security_group.eks_cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound from EKS control plane"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-egress-all"
  })
}

# ── EKS Node SG Rules ─────────────────────────────────────────────────────────

resource "aws_vpc_security_group_ingress_rule" "eks_node_from_cluster" {
  security_group_id            = aws_security_group.eks_node.id
  referenced_security_group_id = aws_security_group.eks_cluster.id
  ip_protocol                  = "-1"
  description                  = "Allow all traffic from EKS control plane to nodes"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-node-from-cluster"
  })
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_self" {
  security_group_id            = aws_security_group.eks_node.id
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "-1"
  description                  = "Allow inter-node communication"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-node-self"
  })
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_from_alb_nodeport" {
  security_group_id            = aws_security_group.eks_node.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767
  description                  = "NodePort traffic from ALB to nodes"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-node-from-alb-nodeport"
  })
}

resource "aws_vpc_security_group_egress_rule" "eks_node_all_outbound" {
  security_group_id = aws_security_group.eks_node.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound from EKS worker nodes"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-node-egress-all"
  })
}

# ── RDS SG Rules ──────────────────────────────────────────────────────────────

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks_nodes" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  description                  = "MySQL access from EKS worker nodes only"

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-rds-from-eks-nodes"
    Component = "database"
  })
}

# ── ALB SG Rules ──────────────────────────────────────────────────────────────

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_internet" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP from internet (redirected to HTTPS by ALB listener)"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-http-from-internet"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https_from_internet" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from internet"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-https-from-internet"
  })
}

resource "aws_vpc_security_group_egress_rule" "alb_to_nodes_nodeport" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767
  description                  = "NodePort range to EKS worker nodes (target group traffic)"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-to-nodes-nodeport"
  })
}

resource "aws_vpc_security_group_egress_rule" "alb_to_nodes_health_check" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  description                  = "Health check traffic to API Gateway port on EKS nodes"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-to-nodes-health-check"
  })
}
