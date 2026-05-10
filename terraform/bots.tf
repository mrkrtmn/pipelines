# Una invocación del módulo bot-service por cada bot.
# Para agregar uno nuevo: copiar el bloque, cambiar nombre y secret_keys, terraform apply.

module "faitpro_bot" {
  source = "./modules/bot-service"

  project_name = "faitpro-bot"
  region       = var.region

  cluster_arn             = aws_ecs_cluster.main.arn
  subnet_ids              = aws_subnet.public[*].id
  security_group_id       = aws_security_group.ecs_tasks.id
  task_execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  tenant_config = "config/faitpro.yml"

  secret_keys = [
    "OPENAI_API_KEY",
    "META_PHONE_NUMBER_ID",
    "META_ACCESS_TOKEN",
    "META_APP_SECRET",
    "META_VERIFY_TOKEN",
    "TELEGRAM_BOT_TOKEN",
    "TELEGRAM_CHAT_ID",
    "AZURE_TENANT_ID",
    "AZURE_CLIENT_ID",
    "AZURE_CLIENT_SECRET",
    "CALENDAR_EMAIL",
    "MAILGUN_API_KEY",
    "MAILGUN_DOMAIN",
    "MAILGUN_FROM_EMAIL"
  ]
}
