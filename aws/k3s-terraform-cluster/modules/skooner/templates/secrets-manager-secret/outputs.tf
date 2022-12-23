output "secret_arn" {
  value = aws_secretsmanager_secret_version.this.arn
}

output "secret_id" {
  value = aws_secretsmanager_secret.this.id
}

output "version_id" {
  value = aws_secretsmanager_secret_version.this.version_id
}