locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "database"
    },
    var.tags,
  )
}

# ── Database Credentials (PETPLAT-23) ─────────────────────────────────────────
# Password is generated here and stored in Secrets Manager.
# RDS reads the password directly from the random resource (not from Secrets Manager).
# External Secrets Operator later syncs the secret to K8s for application use.
#
# Safe special character set: excludes @ " ' / ` \ which can break MySQL URLs
# and JDBC connection strings.

resource "random_password" "db" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]<>:?"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "aws_secretsmanager_secret" "db" {
  name = "petclinic/${var.environment}/rds-credentials"

  # recovery_window_in_days = 0 allows immediate deletion during terraform destroy,
  # which is useful in a learning environment with frequent stack teardowns.
  # Change to 7 or 30 in a long-lived production environment.
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = "petclinic"
    password = random_password.db.result
  })
}

# ── DB Parameter Group ────────────────────────────────────────────────────────
# Full Unicode support: utf8mb4 handles emoji and all Unicode characters,
# required for international pet names and vet notes.

resource "aws_db_parameter_group" "mysql8" {
  name   = "${local.name_prefix}-mysql8"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mysql8-params"
  })
}

# ── DB Subnet Group ───────────────────────────────────────────────────────────
# Subnets span 2 AZs (AWS requires ≥2 AZs in a DB subnet group).
# All subnets are public (all-public design, see ADR-0001), but
# publicly_accessible = false on the instance prevents a public endpoint.

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

# ── RDS MySQL Instance (PETPLAT-22) ───────────────────────────────────────────
#
# DATABASE INITIALIZATION STRATEGY (PETPLAT-24)
# -----------------------------------------------
# Strategy: Spring Boot auto-initialization via spring.sql.init.mode=always
# with the `mysql` Spring profile active.
#
# Each service contains SQL scripts at src/main/resources/db/mysql/ that run
# on first startup when the mysql profile is active. All three services share
# the SAME database: `petclinic` (confirmed by cross-service FK constraint:
# visits.pet_id → pets.id which is created by customers-service).
#
# DEPLOYMENT ORDER (enforced by K8s init containers):
#   1. customers-service  → creates: types, owners, pets
#   2. vets-service       → creates: vets, specialties, vet_specialties
#   3. visits-service     → creates: visits (FK: visits.pet_id → pets.id)
#
# JDBC CONNECTION STRING FORMAT for K8s ConfigMaps:
#   jdbc:mysql://<endpoint>:3306/petclinic
#   Example: jdbc:mysql://petclinic-dev-mysql.xyz.eu-central-1.rds.amazonaws.com:3306/petclinic
#
# Credentials are injected via K8s Secrets synced from Secrets Manager by ESO:
#   SPRING_DATASOURCE_URL      = jdbc:mysql://<endpoint>:3306/petclinic
#   SPRING_DATASOURCE_USERNAME = from secret petclinic/{env}/rds-credentials
#   SPRING_DATASOURCE_PASSWORD = from secret petclinic/{env}/rds-credentials
#
# The `db_name = "petclinic"` argument below creates the initial database on RDS.

resource "aws_db_instance" "main" {
  identifier     = "${local.name_prefix}-mysql"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.instance_class

  db_name  = "petclinic"
  username = "petclinic"
  password = random_password.db.result

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.mysql8.name

  multi_az            = var.multi_az
  publicly_accessible = false

  backup_retention_period   = var.backup_retention_period
  backup_window             = "03:00-04:00"
  maintenance_window        = "Mon:04:00-Mon:05:00"
  auto_minor_version_upgrade = true

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-mysql-final-snapshot"
  deletion_protection       = var.deletion_protection

  # Ensure the secret exists before creating RDS so credentials are available
  # immediately after apply without a second run.
  depends_on = [aws_secretsmanager_secret_version.db]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mysql"
  })
}
