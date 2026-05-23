# Projeto Integrador – Cloud Developing 2026/1

> CRUD simples + API Gateway + Lambda /report + RDS + Front

**Grupo**:

1. 10426655 - Júlia DAgrella - Back-end (API Node.js + RDS) + Infraestrutura AWS (ECS, RDS) + API Gateway + Lambda + Vídeo
2. 10437533 - Rafael Carvalho - Front-end
3. 10439486 - Pedro Henrique - Documentação

---

## 1. Visão geral

**Domínio escolhido:** Catálogo de Filmes

O sistema permite que usuários gerenciem um catálogo de filmes via uma interface web simples. A entidade principal é `filmes`, exposta por uma API REST que oferece as 4 operações CRUD (Create, Read, Update, Delete). Um endpoint `/report`, implementado como função AWS Lambda, consome a API e retorna estatísticas em JSON (total de filmes, nota média, distribuição por gênero e por década), sem acessar o banco de dados diretamente.

---

## 2. Arquitetura

```
Usuário
  │  HTTPS
  ▼
Front-end (S3 Static Website · HTML/CSS/JS)
  │  via API Gateway (HTTPS)
  ▼
Amazon API Gateway
  ├── /items*  ──────────────►  Back-end (ECS Fargate · Node.js/Express)
  │                                        │  SQL (porta 3306)
  │                                        ▼
  │                               Amazon RDS MySQL 8.0
  │
  └── /report  ──────────────►  AWS Lambda (Node.js)
                                  │  HTTP GET /items
                                  └──────────────────► Back-end
```

| Camada | Serviço | Descrição |
|--------|---------|-----------|
| Front-end | Amazon S3 (Static Website) | HTML/CSS/JS estático hospedado no S3 |
| Gateway | Amazon API Gateway | Roteia `/items*` → ECS e `/report` → Lambda |
| Back-end | ECS Fargate | API REST Node.js/Express |
| Banco | Amazon RDS MySQL 8.0 | Instância db.t3.micro |
| Relatório | AWS Lambda | Consome `/items`, gera JSON de estatísticas |

### URLs do projeto em produção

- **Frontend:** http://catalogo-filmes-frontend-078433732491.s3-website-us-east-1.amazonaws.com
- **API Gateway:** https://dyt0vjwv91.execute-api.us-east-1.amazonaws.com/prod
- **Itens:** https://dyt0vjwv91.execute-api.us-east-1.amazonaws.com/prod/items
- **Relatório:** https://dyt0vjwv91.execute-api.us-east-1.amazonaws.com/prod/report

---

## 3. Como rodar localmente

### Pré-requisitos
- Docker Desktop instalado
- Porta 3000 e 8080 disponíveis

```bash
# 1. Clone o repositório
git clone https://github.com/seu-grupo/catalogo-filmes.git
cd catalogo-filmes

# 2. Configure as variáveis de ambiente
cp backend/.env.example backend/.env

# 3. Suba todos os serviços
docker compose up --build

# 4. Acesse
# Front-end: http://localhost:8080
# API:       http://localhost:3000/items
# Health:    http://localhost:3000/health
```

---

## 4. Endpoints da API

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/items` | Lista todos os filmes |
| GET | `/items/:id` | Retorna um filme por ID |
| POST | `/items` | Cria um novo filme |
| PUT | `/items/:id` | Atualiza um filme |
| DELETE | `/items/:id` | Remove um filme |
| GET | `/report` | Relatório JSON (via Lambda) |

### Exemplo de payload (POST/PUT)
```json
{
  "titulo":  "Interstellar",
  "diretor": "Christopher Nolan",
  "ano":     2014,
  "genero":  "Ficção Científica",
  "sinopse": "Uma equipe viaja além da galáxia em busca de um novo lar.",
  "nota":    8.7
}
```

### Exemplo de resposta do /report
```json
{
  "gerado_em": "2026-05-23T22:00:00.000Z",
  "stats": {
    "total_filmes":  4,
    "nota_media":    8.8,
    "nota_maxima":   9.2,
    "nota_minima":   8.5,
    "melhor_filme":  { "titulo": "O Poderoso Chefão", "nota": 9.2 },
    "por_genero":    { "Drama": 2, "Ficção Científica": 1, "Thriller": 1 },
    "por_decada":    { "1970s": 1, "2010s": 2, "1990s": 1 }
  }
}
```

---

## 5. Deploy na AWS

### 5.1 RDS MySQL
1. Criar instância RDS MySQL 8.0 (db.t3.micro)
2. Configurar usuário `admin` e senha
3. Liberar porta 3306 no security group para o ECS

### 5.2 ECR & ECS (Back-end)
```bash
# Autenticar no ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Criar repositório
aws ecr create-repository --repository-name catalogo-filmes-backend

# Build e push
docker build -t catalogo-filmes-backend ./backend
docker tag catalogo-filmes-backend:latest \
  <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/catalogo-filmes-backend:latest
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/catalogo-filmes-backend:latest
```

```bash
# Criar cluster ECS
aws ecs create-cluster --cluster-name catalogo-filmes-cluster --region us-east-1

# Registrar Task Definition com variáveis de ambiente do RDS
# Criar serviço com Fargate
aws ecs create-service --cluster catalogo-filmes-cluster \
  --service-name backend-service \
  --task-definition catalogo-filmes-backend:1 \
  --desired-count 1 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[SUBNET_ID],securityGroups=[SG_ID],assignPublicIp=ENABLED}"
```

### 5.3 Frontend no S3
```bash
# Criar bucket e habilitar site estático
aws s3 mb s3://catalogo-filmes-frontend-<ACCOUNT_ID> --region us-east-1
aws s3 website s3://catalogo-filmes-frontend-<ACCOUNT_ID> --index-document index.html

# Configurar acesso público e fazer upload
aws s3api put-public-access-block --bucket catalogo-filmes-frontend-<ACCOUNT_ID> \
  --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
aws s3 cp frontend/public/index.html s3://catalogo-filmes-frontend-<ACCOUNT_ID>/index.html
```

### 5.4 Lambda /report
```bash
cd lambda && zip function.zip index.js

aws lambda create-function --function-name report-filmes \
  --runtime nodejs20.x \
  --role arn:aws:iam::<ACCOUNT_ID>:role/LabRole \
  --handler index.handler \
  --zip-file fileb://function.zip \
  --environment "Variables={BACKEND_URL=http://<BACKEND_IP>:3000}" \
  --timeout 15
```

### 5.5 API Gateway
```bash
# Criar API
aws apigatewayv2 create-api --name catalogo-filmes-api --protocol-type HTTP \
  --cors-configuration AllowOrigins="*",AllowMethods="GET,POST,PUT,DELETE,OPTIONS"

# Criar integrações e rotas
# /items → ECS backend
# /report → Lambda
# Deploy no stage prod
aws apigatewayv2 create-stage --api-id <API_ID> --stage-name prod --auto-deploy
```

---

## 6. Estrutura do repositório

```
catalogo-filmes/
├── backend/
│   ├── Dockerfile
│   ├── package.json
│   ├── .env.example
│   └── src/
│       ├── server.js
│       ├── routes/filmes.js
│       └── config/
│           ├── database.js
│           └── init.sql
├── frontend/
│   ├── Dockerfile
│   └── public/index.html
├── lambda/
│   └── index.js
├── docs/
│   └── arquitetura.png
├── docker-compose.yml
├── iniciar.bat
└── README.md
```

---

## 7. Observações sobre o ambiente de laboratório

O projeto foi desenvolvido no AWS Academy Learner Lab, que possui algumas restrições de permissões. Por isso:

- O **frontend** foi hospedado no **Amazon S3** como site estático em vez do ECS Fargate, pois o S3 oferece URL fixa HTTPS que resolve o problema de mixed content com o API Gateway.
- O **banco de dados** utiliza **Amazon RDS MySQL 8.0** conforme requisito do projeto.
- As credenciais do laboratório expiram a cada sessão, sendo necessário reconfigurá-las ao iniciar uma nova sessão.
