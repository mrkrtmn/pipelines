// Configuración por proyecto. Cada entrada describe un bot a desplegar.
// Para agregar un proyecto nuevo:
//   1. Agregar entrada en este map
//   2. Agregar `module "<nombre>"` en terraform/bots.tf y outputs en terraform/outputs.tf
//   3. terraform apply
//   4. Setear los secrets reales con `aws secretsmanager put-secret-value`
//   5. En Jenkins: el dropdown PROJECT debe incluir esta key (ver botwb.jenkinsfile)
//
// Notas:
//   - `containerName` debe coincidir con el nombre del container en el task definition
//     creado por terraform/modules/bot-service (por defecto: "bot")
//   - `ecrRepo`, `ecsCluster`, `ecsService`, `taskFamily` los crea Terraform
//   - Cada deploy: Jenkins lee el task def vigente, reemplaza la imagen del container
//     `containerName` con la nueva del ECR, registra nueva revisión, hace update-service

return [
    'faitpro-bot': [
        githubRepo:    'https://github.com/mrkrtmn/FAITPro-bot.git',
        branch:        'main',
        awsRegion:     'us-east-1',
        ecrRepo:       'faitpro-bot',
        ecsCluster:    'botwb-cluster',
        ecsService:    'faitpro-bot',
        taskFamily:    'faitpro-bot',
        containerName: 'bot'
    ]
]
