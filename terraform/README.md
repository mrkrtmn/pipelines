# Terraform — infra AWS para botwb

Provisiona la infraestructura compartida (VPC, ECS Fargate cluster, IAM) y los recursos por bot (ECR repo, log group, secrets, task definition, ECS service) para correr bots de WhatsApp en AWS con Cloudflare Tunnel sidecar.

**No requiere ALB, NAT Gateway ni Route 53** → costo aprox. $10/mes por bot 24/7.

## Estructura

```
terraform/
├── versions.tf, providers.tf, variables.tf
├── vpc.tf                     # VPC + 2 subnets públicas + IGW + SG egress-only
├── ecs-cluster.tf             # ECS cluster (Fargate + Fargate Spot)
├── iam-jenkins.tf             # IAM user + access key para Jenkins
├── iam-task.tf                # task execution role + task role
├── bots.tf                    # invocaciones del módulo bot-service por bot
├── outputs.tf
├── terraform.tfvars.example
└── modules/
    └── bot-service/           # ECR + secrets + task def + service por bot
```

## Setup inicial (una sola vez)

```bash
# 1. Configurá el AWS CLI con credenciales de admin (un IAM user con power user o admin)
aws configure
# o exportá AWS_ACCESS_KEY_ID/SECRET_ACCESS_KEY/AWS_REGION en el entorno

# 2. Variables
cp terraform.tfvars.example terraform.tfvars   # editar si hace falta

# 3. Apply
terraform init
terraform plan
terraform apply

# 4. Obtener las credenciales para Jenkins
terraform output -raw jenkins_access_key_id
terraform output -raw jenkins_secret_access_key
```

Esas dos credenciales se cargan en **Jenkins → Manage Jenkins → Credentials → Global** como una credencial de tipo "AWS Credentials" con id `aws-jenkins`.

## Setear los secrets reales (después de `terraform apply`)

Terraform crea cada secret con valor `PLACEHOLDER_REPLACE_ME`. Hay que rellenarlos:

```bash
# App secrets
for KEY in OPENAI_API_KEY META_ACCESS_TOKEN META_APP_SECRET META_VERIFY_TOKEN \
           META_PHONE_NUMBER_ID TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID \
           AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET CALENDAR_EMAIL \
           MAILGUN_API_KEY MAILGUN_DOMAIN MAILGUN_FROM_EMAIL; do
  read -rsp "Valor de ${KEY}: " VALUE
  echo
  aws secretsmanager put-secret-value \
    --secret-id "faitpro-bot/${KEY}" \
    --secret-string "${VALUE}"
done

# Cloudflare Tunnel token
read -rsp "Cloudflare Tunnel token: " TOKEN
echo
aws secretsmanager put-secret-value \
  --secret-id "faitpro-bot/cloudflare-tunnel-token" \
  --secret-string "${TOKEN}"
```

El `terraform output faitpro_bot_app_secret_names` lista los nombres exactos de los secrets para no equivocarse.

## Cloudflare Tunnel — pasos por bot

1. Cloudflare dashboard → Zero Trust → Networks → Tunnels → **Create a tunnel**
2. Tipo: **Cloudflared**, nombre: `faitpro-bot` (o el que sea)
3. Copiar el **token** generado
4. Configurar **Public Hostnames** del tunnel:
   - Subdomain: `wa`, Domain: `faitpro.com.bo`
   - Service: `http://localhost:8000` (puerto interno de la task; el sidecar y el bot comparten localhost)
5. Pegar el token en Secrets Manager:
   ```bash
   aws secretsmanager put-secret-value --secret-id faitpro-bot/cloudflare-tunnel-token --secret-string "<token>"
   ```
6. Forzar redeploy del service para que la task tome el nuevo valor:
   ```bash
   aws ecs update-service --cluster botwb-cluster --service faitpro-bot --force-new-deployment
   ```

## Agregar un bot nuevo

```hcl
# bots.tf — copiar el bloque y ajustar
module "sabornacional" {
  source = "./modules/bot-service"

  project_name = "sabornacional"
  region       = var.region

  cluster_arn             = aws_ecs_cluster.main.arn
  subnet_ids              = aws_subnet.public[*].id
  security_group_id       = aws_security_group.ecs_tasks.id
  task_execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  tenant_config = "config/sabornacional.yml"
  secret_keys = ["OPENAI_API_KEY", "META_ACCESS_TOKEN", ...]
}
```

```hcl
# outputs.tf — exponer outputs útiles
output "sabornacional_ecr_url"          { value = module.sabornacional.ecr_repository_url }
output "sabornacional_app_secret_names" { value = module.sabornacional.app_secret_names }
```

Después:
1. `terraform apply`
2. Editar `../projects.groovy` y agregar la entrada del nuevo proyecto
3. Setear secrets con CLI
4. Crear el tunnel en Cloudflare y pegar el token
5. En Jenkins, editar el job para agregar el nombre nuevo al `choices` del param `PROJECT` (en `botwb.jenkinsfile`)
6. Build with parameters → seleccionar el nuevo bot → run

## Costo estimado por bot 24/7

| Recurso | Costo/mes |
|---|---|
| Fargate 0.25 vCPU + 0.5 GB | ~$9 |
| Cloudflared sidecar (extra ~64 MB de RAM) | incluido en el task |
| ECR (storage de hasta 10 imágenes) | <$0.10 |
| Secrets Manager (~15 secrets × $0.40) | ~$6 |
| CloudWatch Logs (14 días retention, tráfico bajo) | ~$0.50 |
| **Total estimado** | **~$15-16/mes** |

> ⚠️ Secrets Manager cobra **$0.40/secret/mes**. Si llegas a tener muchos bots y querés bajar costo, cambiar a **SSM Parameter Store SecureString** ($0 si <10k params) — requiere cambiar el módulo `bot-service` para usar `aws_ssm_parameter` en lugar de `aws_secretsmanager_secret` y referenciarlos como `arn:aws:ssm:<region>:<acct>:parameter/<name>` en `secrets[].valueFrom`.

Cloudflare Tunnel = **gratis siempre**.

## Recursos compartidos (no escalan con el nº de bots)

- VPC + IGW + 2 subnets: $0 (lo de IPv4 público lo paga el assign_public_ip de cada task: ~$3.65/mes por task con IP pública en us-east-1)
- ECS cluster: $0
- IAM user/roles: $0

## Caveat: assign_public_ip y EIP de Fargate

Fargate con `assign_public_ip = true` cobra $0.005/hora por la IP pública asignada (~$3.65/mes/task). Es la opción más barata para bots saliente-only sin NAT Gateway ($32/mo). Si la cuenta termina con muchos bots, evaluar consolidar en private subnet + 1 NAT Gateway compartido.

## terraform destroy

Si vas a tirar todo abajo:

```bash
terraform destroy
```

Los secrets se eliminan inmediatamente (`recovery_window_in_days = 0`). No hay backup automático del state — guardalo aparte si te importa.
