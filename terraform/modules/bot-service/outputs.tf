output "ecr_repository_url" {
  description = "URL del ECR repo (para docker push)"
  value       = aws_ecr_repository.this.repository_url
}

output "ecs_service_name" {
  description = "Nombre del ECS service"
  value       = aws_ecs_service.this.name
}

output "task_family" {
  description = "Nombre de la familia de task definitions"
  value       = aws_ecs_task_definition.this.family
}

output "log_group_name" {
  description = "CloudWatch log group de los containers"
  value       = aws_cloudwatch_log_group.this.name
}

output "secret_arns" {
  description = "ARNs de los secrets de la app, indexados por key"
  value       = { for k, v in aws_secretsmanager_secret.app : k => v.arn }
}

output "cloudflare_tunnel_secret_arn" {
  description = "ARN del secret donde va el token del Cloudflare Tunnel"
  value       = aws_secretsmanager_secret.cloudflare_tunnel_token.arn
}

output "cloudflare_tunnel_secret_name" {
  description = "Nombre del secret del CF tunnel (para poner el valor con CLI)"
  value       = aws_secretsmanager_secret.cloudflare_tunnel_token.name
}

output "app_secret_names" {
  description = "Nombres de los secrets de la app (para poner los valores con CLI)"
  value       = [for s in aws_secretsmanager_secret.app : s.name]
}
