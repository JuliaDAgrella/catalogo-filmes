# Projeto Integrador – Cloud Developing 2026/1

> CRUD simples + API Gateway + Lambda /report + RDS + Front

**Grupo**:

<!-- no máximo 5 alunos -->
1. RA - nome - Back-end (API Node.js + RDS)
2. RA - nome - Infraestrutura AWS (ECS, RDS, VPC)
3. RA - nome - API Gateway + Lambda
4. RA - nome - Front-end
5. RA - nome - Documentação + Vídeo

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
Front-end (ECS Fargate · nginx + HTML/JS)
  │  via API Gateway
  ▼
Amazon API Gateway
  ├── /items*  ──────────────►  Back-end (ECS Fargate · Node.js/Express)
  │                                        │  SQL
  │                                        ▼
  │                               Amazon RDS MySQL
  │                               (subnet privada)
  │
  └── /report  ──────────────►  AWS Lambda (Node.js)
                                  │  HTTP GET /items
                                  └──────────────────► Back-end
```

| Camada | Serviço | Descrição |
|--------|---------|-----------|
| Front-end | ECS Fargate | nginx servindo HTML/CSS/JS estático |
| Gateway | Amazon API Gateway | Roteia `/items*` → ECS e `/report` → Lambda |
| Back-end | ECS Fargate | API REST Node.js/Express |
| Banco | Amazon RDS MySQL | Subnet privada, porta 3306 não exposta |
| Relatório | AWS Lambda | Consome `/items`, gera JSON de estatísticas |

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
# (para rodar local não precisa alterar nada — o docker-compose já injeta as vars)

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
  "gerado_em": "2026-05-10T20:00:00.000Z",
  "stats": {
    "total_filmes":  4,
    "nota_media":    8.8,
    "nota_maxima":   9.2,
    "nota_minima":   8.5,
    "melhor_filme":  { "titulo": "O Poderoso Chefão", "nota": 9.2 },
    "por_genero":    { "Crime/Drama": 1, "Ficção Científica": 1, "Thriller": 1, "Drama/Thriller": 1 },
    "por_decada":    { "1970s": 1, "2010s": 2, "1990s": 1 }
  }
}
```

---

## 5. Deploy na AWS (passo a passo)

### 5.1 VPC & RDS
1. Crie uma VPC com 2 subnets **privadas** (sem route para internet) e 2 **públicas**.
2. Crie um **Security Group** `sg-rds` que permite entrada na porta 3306 **apenas** do `sg-backend`.
3. Crie o **Amazon RDS MySQL 8.0**:
   - Instância: `db.t3.micro` (free tier)
   - Subnet group: as 2 subnets privadas
   - Security group: `sg-rds`
   - **Publicly accessible: NO**
4. Conecte ao RDS pelo bastion ou AWS Systems Manager e execute `backend/src/config/init.sql`.

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

5. Crie um **ECS Cluster** (Fargate).
6. Crie uma **Task Definition** apontando para a imagem ECR; configure as variáveis de ambiente (`DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`).
7. Crie um **Service** no cluster com 1 instância, em subnet privada + Application Load Balancer (porta 3000).

### 5.3 ECR & ECS (Front-end)
Repita o 5.2 para `./frontend`. O front-end vai em subnet **pública** na porta 80.  
Antes de fazer o push, edite `frontend/public/index.html` e substitua `window.ENV_API_URL` pela URL do API Gateway.

### 5.4 Lambda /report
1. Comprima a pasta `lambda/`:
   ```bash
   cd lambda && zip function.zip index.js
   ```
2. Crie a função Lambda:
   - Runtime: Node.js 20.x
   - Handler: `index.handler`
   - Variável de ambiente: `BACKEND_URL=http://<URL-interna-do-ALB-backend>`
3. Configure o timeout para **15 segundos**.

### 5.5 API Gateway
1. Crie uma **REST API** (HTTP API).
2. Integração 1: qualquer rota `/items/{proxy+}` → **HTTP proxy** para o ALB do back-end.
3. Integração 2: rota `GET /report` → **Lambda** (`report-filmes`).
4. **Deploy** no stage `prod`.
5. Copie a URL do stage e cole no front-end (`window.ENV_API_URL`).

---

## 6. Checklist de entrega

- [x] API CRUD cobre 4 operações essenciais (GET, POST, PUT, DELETE)
- [x] Banco RDS criado em subnet privada; porta 3306 não exposta
- [x] Imagem Docker com tag correspondente ao commit apresentado
- [x] API Gateway roteando `/items*` → ECS e `/report` → Lambda
- [x] Função Lambda consome a API (`/items`) via HTTP, gera JSON de relatório. **Não** toca no RDS
- [x] README completo + diagrama de arquitetura em `docs/arquitetura.png`
- [ ] PDF (≤ 12 pág.) com capturas de tela e descrição de funções dos integrantes
- [ ] Vídeo (≤ 5 min) demonstrando CRUD, chamada `/report` e execução do pipeline
- [ ] ZIP final contém `README.md`, código-fonte, `infra/` (IaC), PDF e link do vídeo

---

## 7. Estrutura do repositório

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
│   └── arquitetura.png        ← exporte o diagrama para cá
├── docker-compose.yml
└── README.md
```
