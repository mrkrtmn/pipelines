# pipelines

Jenkinsfiles + módulos Terraform para deploy multi-proyecto de bots WhatsApp.

```
pipelines/
├── botwb.jenkinsfile          # pipeline parametrizado: deploy de bots a ECS Fargate
├── projects.groovy            # config por proyecto (un map). Agregar bots aquí
├── git_tag.jenkinsfile        # pipeline existente para crear tags (no relacionado)
└── terraform/                 # infra AWS (ver terraform/README.md)
```

## Arquitectura del deploy (`botwb.jenkinsfile`)

```
GitHub repo del bot
       │ git pull
       ▼
Jenkins agent-1 (on-prem srv03)
       │  docker build
       │  docker push
       ▼
ECR repo del bot                         <── creado por Terraform
       │
       │  register-task-definition (nueva revision con la nueva imagen)
       │  update-service --task-definition <new>
       ▼
ECS Fargate service                      <── creado por Terraform
   ├─ container "bot" (FastAPI puerto 8000)
   └─ container "cloudflared" (sidecar) ─── tunnel ──> Cloudflare ──> wa.<dominio>.com.bo
```

## Setup inicial (una vez)

### 1. Provisionar la infra con Terraform

Ver `terraform/README.md`. En resumen:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
terraform output -raw jenkins_access_key_id
terraform output -raw jenkins_secret_access_key
```

### 2. Credenciales en Jenkins

**Manage Jenkins → Credentials → Global → Add Credentials**:

| Kind | ID | Contenido |
|------|----|-----------|
| AWS Credentials | `aws-jenkins` | Access Key ID + Secret Access Key del output de Terraform |
| Username with password | `github-pat` | username: tu user de GitHub · password: PAT con scope `repo` |

### 3. Plugins de Jenkins requeridos

- **Pipeline: AWS Steps** → para `withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', ...]])`
- **CloudBees AWS Credentials** → tipo de credencial AWS
- **Pipeline: Utility Steps** → `readFile`, `fileExists`, `load`
- **Workspace Cleanup** → `cleanWs()`
- **Git** → checkout

### 4. Herramientas en `agent-1`

El pipeline corre en el agente `agent-1`. Necesita:

- **docker** (para build/push)
- **awscli v2** (`aws`)
- **jq** (para mutar el task definition JSON)
- **git**

Si falta alguna, agregar en el `Dockerfile` del agente (en `~/Repo/Devstack/jenkins/agent-1/Dockerfile` o similar):

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip jq git docker.io \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/aws.zip \
    && unzip /tmp/aws.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/aws.zip \
    && rm -rf /var/lib/apt/lists/*
```

> El agente `jenkins-agent-1` ya monta `/var/run/docker.sock` (vi en docker-compose), así que `docker build` funciona con el daemon del host.

### 5. Crear el job en Jenkins

1. **New Item → Pipeline**, nombre: `botwb-deploy`
2. **Pipeline** → **Definition: Pipeline script from SCM**
3. **SCM**: Git
   - URL: URL del repo `pipelines` en GitHub (después de migrar)
   - Credentials: `github-pat`
   - Branch: `main`
4. **Script Path**: `botwb.jenkinsfile`
5. Save → **Build with parameters**

## Setear los secrets reales

Después del primer `terraform apply`, los secrets viven en AWS Secrets Manager con valor `PLACEHOLDER_REPLACE_ME`. Hay que rellenarlos. Ver `terraform/README.md` sección "Setear los secrets reales".

## Configurar Cloudflare Tunnel del bot

Ver `terraform/README.md` sección "Cloudflare Tunnel — pasos por bot". TL;DR:

1. Cloudflare dashboard → Zero Trust → Tunnels → Create
2. Public hostname: `wa.<dominio>` → `http://localhost:8000`
3. Token → `aws secretsmanager put-secret-value --secret-id <bot>/cloudflare-tunnel-token`
4. `aws ecs update-service --force-new-deployment` para que la task tome el token

## Agregar un proyecto nuevo (paso a paso)

1. **Terraform** (`terraform/bots.tf`): copiar el bloque `module "faitpro_bot"`, cambiar `project_name`, `tenant_config`, `secret_keys`. Agregar outputs en `terraform/outputs.tf`. → `terraform apply`.
2. **projects.groovy**: agregar entrada con `githubRepo`, `branch`, `awsRegion`, `ecrRepo`, `ecsCluster`, `ecsService`, `taskFamily`, `containerName`.
3. **botwb.jenkinsfile**: agregar el nombre nuevo al array `choices` del parámetro `PROJECT`.
4. **AWS**: setear los secrets reales con CLI.
5. **Cloudflare**: crear el tunnel, pegar token en Secrets Manager.
6. Push los cambios → Jenkins lee el `botwb.jenkinsfile` actualizado en el próximo run.
7. **Build with parameters** → seleccionar el nuevo proyecto → deploy.

## Cómo deployar

**Manual (UI)**:
1. Jenkins → `botwb-deploy` → **Build with parameters**
2. Elegir `PROJECT` del dropdown
3. (Opcional) `IMAGE_TAG` custom; si vacío usa el short SHA
4. Build

**Automático con webhook GitHub** (opcional, paso 2):
- En el repo del bot → Settings → Webhooks → `https://jenkins.faitpro.com.bo/github-webhook/`
- Plugin "GitHub" en Jenkins detecta el push y dispara el job
- Para que sepa qué proyecto desplegar, usar un job por bot (cada uno con `PROJECT` fijo) o un job que mire el repo URL del payload — más complejo, dejar para después.

## Costo total estimado

| Recurso | Costo/mes |
|---|---|
| Por bot (Fargate + secrets + ECR + logs) | ~$15-16 |
| VPC + ECS cluster + IAM | $0 |
| Cloudflare Tunnel | $0 |
| Jenkins + agent (on-prem srv03) | $0 |
| **1 bot total** | **~$16** |
| **3 bots total** | **~$48** |

Si llega a 5+ bots, vale la pena bajar costo de Secrets Manager pasando a SSM Parameter Store ($0 vs $6/mes por bot) — ver nota en `terraform/README.md`.
