# pipelines

Jenkinsfile + projects.groovy para el deploy del **código** de los bots WhatsApp a AWS ECS Fargate.

> **La infraestructura AWS (terraform) NO vive en este repo.** Se movió a [`mrkrtmn/IaC`](https://github.com/mrkrtmn/IaC) en mayo 2026. Este repo solo tiene el pipeline de deploy del contenedor.

```
pipelines/
├── botwb.jenkinsfile          # pipeline parametrizado: build imagen → push ECR → update ECS service
├── projects.groovy            # config por proyecto/bot (un map). Agregar bots nuevos acá
└── git_tag.jenkinsfile        # pipeline de tags (sin relación con el deploy de bots)
```

## Arquitectura del deploy (`botwb.jenkinsfile`)

```
GitHub repo del bot (ej. mrkrtmn/FAITPro-bot)
       │ git pull
       ▼
Jenkins agent-1 (on-prem srv03)
       │  docker build (con el Dockerfile del repo del bot)
       │  docker push  (a ECR)
       ▼
ECR repo del bot                         <── creado por mrkrtmn/IaC
       │
       │  aws ecs describe-task-definition  (lee la rev vigente)
       │  jq edita el image del container `bot`
       │  aws ecs register-task-definition  (rev nueva)
       │  aws ecs update-service             (apunta el service a la rev nueva)
       │  aws ecs wait services-stable       (espera rolling deploy)
       ▼
ECS Fargate service                      <── creado por mrkrtmn/IaC
   ├─ container "bot" (FastAPI puerto 8000)
   └─ container "cloudflared" (sidecar) ─── tunnel saliente ──> Cloudflare ──> wa-aws.<dominio>
```

El pipeline **NO toca** `desired_count` del service — solo cambia qué imagen corre. Si necesitás escalar, hacelo con `aws ecs update-service --desired-count N` directamente.

## Setup inicial

Asume que la infraestructura AWS ya está aplicada (ver [mrkrtmn/IaC/README.md](https://github.com/mrkrtmn/IaC) sección "Bootstrap desde cero").

### 1. Credenciales en Jenkins

Configuradas en https://jenkins.faitpro.com.bo/credentials/:

| Kind | ID | Contenido |
|------|----|-----------|
| Username with password | `aws-jenkins` | username = AWS access key id del IAM user `botwb-jenkins`, password = AWS secret access key |
| Username with password | `github-pat` | username = tu user de GitHub · password = PAT con scope `repo` |

La cred `aws-jenkins` se genera en el bootstrap de IaC (`scripts/bootstrap-iam.sh`). Permisos restringidos a ECR + ECS + PassRole (no admin).

### 2. Plugins de Jenkins requeridos

- **Pipeline: Utility Steps** → `readFile`, `fileExists`, `load`
- **Workspace Cleanup** → `cleanWs()`
- **Git**
- **Credentials Binding** → `withCredentials(usernamePassword(...))`

### 3. Herramientas en `agent-1`

- `docker` (para build/push)
- `awscli v2` (`aws`)
- `jq` (para mutar el task definition JSON)
- `git`

### 4. Crear el job en Jenkins

1. **New Item → Pipeline**, nombre: `botwb-deploy`
2. **Pipeline → Definition: Pipeline script from SCM**
3. **SCM**: Git
   - URL: `https://github.com/mrkrtmn/pipelines.git`
   - Credentials: `github-pat`
   - Branch: `*/main`
4. **Script Path**: `botwb.jenkinsfile`
5. Save → primer build sin params para que Jenkins descubra los parámetros del pipeline → después **Build with parameters**

## Cómo deployar

**Manual (UI)**:
1. https://jenkins.faitpro.com.bo/job/botwb-deploy/ → **Build with parameters**
2. Elegir `PROJECT` del dropdown (los bots configurados en `projects.groovy`)
3. (Opcional) `IMAGE_TAG` custom; si vacío usa el short SHA del commit
4. `PRUNE_AFTER` (default true) → docker image prune en el agente al terminar
5. Build

**Automático con webhook GitHub** (opcional):
- En el repo del bot → Settings → Webhooks → `https://jenkins.faitpro.com.bo/github-webhook/`
- Plugin "GitHub" en Jenkins detecta el push y dispara el job
- Para que sepa qué proyecto desplegar, usar un job por bot (cada uno con `PROJECT` fijo)

## Agregar un proyecto nuevo

1. **`mrkrtmn/IaC`**: agregar carpeta `bots/<nuevo-bot>/` con su tfvars y backend. Correr `iac-apply` STACK=`bots/<nuevo-bot>` ACTION=apply.
2. **`projects.groovy` (este repo)**: agregar entrada con `githubRepo`, `branch`, `awsRegion`, `ecrRepo`, `ecsCluster`, `ecsService`, `taskFamily`, `containerName`.
3. **`botwb.jenkinsfile` (este repo)**: agregar el nombre del bot al array `choices` del parámetro `PROJECT`.
4. Setear los SSM secrets del nuevo bot (`aws ssm put-parameter --name "/<nuevo-bot>/..."`).
5. Crear el tunnel en Cloudflare, setear `cloudflare-tunnel-token` en SSM.
6. Commit + push de los dos repos.
7. Jenkins **Build with parameters** → seleccionar el nuevo proyecto → deploy.

## Setear / rotar secrets

Los secrets viven en **AWS SSM Parameter Store**, no en este repo. Para gestionarlos:

```bash
# Rotar un secret
aws ssm put-parameter --name "/<bot>/<KEY>" --value "<VALUE>" \
  --type SecureString --overwrite --region us-east-1

# Force redeploy para que la task tome el secret nuevo
aws ecs update-service --cluster botwb-cluster --service <bot> \
  --force-new-deployment --region us-east-1
```

Ver [mrkrtmn/IaC/docs/SECRETS.md](https://github.com/mrkrtmn/IaC/blob/main/docs/SECRETS.md) para detalles (los 3 lugares donde viven secrets, cómo generar System User tokens permanentes de Meta, etc.).

## Costo total estimado

Ver [mrkrtmn/IaC/README.md → Costo estimado por bot](https://github.com/mrkrtmn/IaC#costo-estimado-por-bot-247).

| Recurso | Costo/mes |
|---|---|
| Por bot (Fargate + ECR + logs + SSM) | ~$13 |
| Jenkins + agent (on-prem srv03) | $0 |
| Cloudflare Tunnel | $0 |
| **1 bot total** | **~$13** |
| **3 bots total** | **~$39** |

## Repos relacionados

- **[mrkrtmn/IaC](https://github.com/mrkrtmn/IaC)** — infraestructura AWS (terraform): VPC, ECS, IAM, SSM, ECR. Pipeline Jenkins `iac-apply` allá.
- **[mrkrtmn/FAITPro-bot](https://github.com/mrkrtmn/FAITPro-bot)** — código Python del bot.
- **este repo** — solo el pipeline `botwb-deploy` que construye imagen y la deploya a la infra existente.
