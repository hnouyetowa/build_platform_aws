output "endpoint" {
  description = "RDS instance endpoint hostname (without port)"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS instance port (3306)"
  value       = aws_db_instance.main.port
}

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}

output "secret_arn" {
  description = "Secrets Manager ARN for RDS credentials — used by External Secrets Operator"
  value       = aws_secretsmanager_secret.db.arn
}

output "connection_url" {
  description = "JDBC connection URL for K8s ConfigMaps: jdbc:mysql://<endpoint>:3306/petclinic"
  value       = "jdbc:mysql://${aws_db_instance.main.address}:${aws_db_instance.main.port}/petclinic"
}

output "db_name" {
  description = "Name of the initial database created on the RDS instance"
  value       = aws_db_instance.main.db_name
}
