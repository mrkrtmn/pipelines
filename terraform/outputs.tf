# --- Compartido ---
output "vpc_id" { value = aws_vpc.main.id }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "ecs_cluster_name" { value = aws_ecs_cluster.main.name }
output "ecs_cluster_arn" { value = aws_ecs_cluster.main.arn }
output "ecs_security_group_id" { value = aws_security_group.ecs_tasks.id }
output "task_execution_role_arn" { value = aws_iam_role.ecs_task_execution.arn }
output "task_role_arn" { value = aws_iam_role.ecs_task.arn }

# --- Credenciales de Jenkins (sensibles) ---
# Obtener con:
#   terraform output -raw jenkins_access_key_id
#   terraform output -raw jenkins_secret_access_key
output "jenkins_access_key_id" {
  value     = aws_iam_access_key.jenkins.id
  sensitive = true
}

output "jenkins_secret_access_key" {
  value     = aws_iam_access_key.jenkins.secret
  sensitive = true
}

# --- Por bot ---
output "faitpro_bot_ecr_url" {
  value = module.faitpro_bot.ecr_repository_url
}

output "faitpro_bot_app_secret_names" {
  description = "Nombres de los secrets de la app (rellenar con aws secretsmanager put-secret-value)"
  value       = module.faitpro_bot.app_secret_names
}

output "faitpro_bot_cloudflare_tunnel_secret_name" {
  value = module.faitpro_bot.cloudflare_tunnel_secret_name
}
