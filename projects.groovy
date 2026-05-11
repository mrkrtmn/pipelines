// Configuración por proyecto. Cada entrada describe un bot a desplegar.
// Para agregar un proyecto nuevo:
//   1. Agregar entrada en este map
//   2. Agregar carpeta `bots/<nombre>/` en mrkrtmn/IaC con su tfvars y backend
//   3. Desde Jenkins iac-apply: STACK=bots/<nombre> ACTION=apply
//   4. Setear los secrets reales con `aws ssm put-parameter --type SecureString --overwrite`
//   5. En Jenkins: el dropdown PROJECT del job botwb-deploy debe incluir esta key (ver botwb.jenkinsfile)
//
// Notas:
//   - `containerName` debe coincidir con el nombre del container en el task definition
//     creado por mrkrtmn/IaC/modules/bot-service (por defecto: "bot")
//   - `ecrRepo`, `ecsCluster`, `ecsService`, `taskFamily` los crea Terraform (mrkrtmn/IaC)
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
