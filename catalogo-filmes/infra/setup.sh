#!/bin/bash
# =============================================================
# IaC - Infraestrutura como Código
# Projeto: Catálogo de Filmes - Cloud Developing 2026/1
# Descrição: Todos os comandos AWS CLI para provisionar
#            a infraestrutura do projeto na AWS
# =============================================================

ACCOUNT_ID="078433732491"
REGION="us-east-1"
CLUSTER="catalogo-filmes-cluster"
ECR="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# =============================================================
# 1. ECR - Elastic Container Registry
# Cria os repositórios para armazenar as imagens Docker
# =============================================================
echo "Criando repositorios ECR..."

aws ecr create-repository \
  --repository-name catalogo-filmes-backend \
  --region $REGION

aws ecr create-repository \
  --repository-name catalogo-filmes-frontend \
  --region $REGION

# =============================================================
# 2. BUILD E PUSH DAS IMAGENS DOCKER
# =============================================================
echo "Autenticando no ECR..."
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ECR

echo "Build e push do backend..."
docker build -t catalogo-filmes-backend ./backend
docker tag catalogo-filmes-backend:latest $ECR/catalogo-filmes-backend:latest
docker push $ECR/catalogo-filmes-backend:latest

echo "Build e push do frontend..."
docker build -t catalogo-filmes-frontend ./frontend
docker tag catalogo-filmes-frontend:latest $ECR/catalogo-filmes-frontend:latest
docker push $ECR/catalogo-filmes-frontend:latest

# =============================================================
# 3. ECS - Elastic Container Service
# Cria o cluster e os serviços do backend
# =============================================================
echo "Criando cluster ECS..."
aws ecs create-cluster \
  --cluster-name $CLUSTER \
  --region $REGION

echo "Registrando Task Definition do backend..."
aws ecs register-task-definition \
  --region $REGION \
  --cli-input-json file://infra/task-definition.json

echo "Obtendo subnet e security group..."
SUBNET=$(aws ec2 describe-subnets --region $REGION \
  --query "Subnets[0].SubnetId" --output text)
SG=$(aws ec2 describe-security-groups --region $REGION \
  --query "SecurityGroups[?GroupName=='default'].GroupId" --output text)

echo "Liberando portas no security group..."
aws ec2 authorize-security-group-ingress \
  --region $REGION --group-id $SG \
  --protocol tcp --port 3000 --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --region $REGION --group-id $SG \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

echo "Criando servico ECS do backend..."
aws ecs create-service \
  --region $REGION \
  --cluster $CLUSTER \
  --service-name backend-service \
  --task-definition catalogo-filmes-backend:1 \
  --desired-count 1 \
  --launch-type FARGATE \
  --enable-execute-command \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET],securityGroups=[$SG],assignPublicIp=ENABLED}"

# =============================================================
# 4. S3 - Frontend estático
# =============================================================
echo "Criando bucket S3 para o frontend..."
aws s3 mb s3://catalogo-filmes-frontend-$ACCOUNT_ID --region $REGION

aws s3 website s3://catalogo-filmes-frontend-$ACCOUNT_ID \
  --index-document index.html

aws s3api put-public-access-block \
  --bucket catalogo-filmes-frontend-$ACCOUNT_ID \
  --public-access-block-configuration \
  "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

aws s3api put-bucket-policy \
  --bucket catalogo-filmes-frontend-$ACCOUNT_ID \
  --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"PublicRead\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::catalogo-filmes-frontend-$ACCOUNT_ID/*\"}]}"

aws s3 cp frontend/public/index.html \
  s3://catalogo-filmes-frontend-$ACCOUNT_ID/index.html

# =============================================================
# 5. LAMBDA - Função /report
# =============================================================
echo "Criando funcao Lambda..."
cd lambda && zip function.zip index.js && cd ..

# Obter IP do backend
TASK_ARN=$(aws ecs list-tasks --region $REGION \
  --cluster $CLUSTER --service-name backend-service \
  --query "taskArns[0]" --output text)
ENI=$(aws ecs describe-tasks --region $REGION \
  --cluster $CLUSTER --tasks $TASK_ARN \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
  --output text)
BACKEND_IP=$(aws ec2 describe-network-interfaces \
  --region $REGION --network-interface-ids $ENI \
  --query "NetworkInterfaces[0].Association.PublicIp" --output text)

aws lambda create-function \
  --region $REGION \
  --function-name report-filmes \
  --runtime nodejs20.x \
  --role arn:aws:iam::$ACCOUNT_ID:role/LabRole \
  --handler index.handler \
  --zip-file fileb://lambda/function.zip \
  --environment "Variables={BACKEND_URL=http://$BACKEND_IP:3000}" \
  --timeout 15

# =============================================================
# 6. API GATEWAY - HTTP API
# =============================================================
echo "Criando API Gateway..."
API_ID=$(aws apigatewayv2 create-api \
  --region $REGION \
  --name catalogo-filmes-api \
  --protocol-type HTTP \
  --cors-configuration AllowOrigins="*",AllowMethods="GET,POST,PUT,DELETE,OPTIONS",AllowHeaders="Content-Type" \
  --query "ApiId" --output text)

echo "Criando integracoes..."
INT_ITEMS=$(aws apigatewayv2 create-integration \
  --region $REGION --api-id $API_ID \
  --integration-type HTTP_PROXY \
  --integration-method ANY \
  --integration-uri http://$BACKEND_IP:3000/items \
  --payload-format-version 1.0 \
  --query "IntegrationId" --output text)

INT_PROXY=$(aws apigatewayv2 create-integration \
  --region $REGION --api-id $API_ID \
  --integration-type HTTP_PROXY \
  --integration-method ANY \
  --integration-uri http://$BACKEND_IP:3000/items/{proxy} \
  --payload-format-version 1.0 \
  --query "IntegrationId" --output text)

LAMBDA_ARN="arn:aws:lambda:$REGION:$ACCOUNT_ID:function:report-filmes"
INT_LAMBDA=$(aws apigatewayv2 create-integration \
  --region $REGION --api-id $API_ID \
  --integration-type AWS_PROXY \
  --integration-uri $LAMBDA_ARN \
  --payload-format-version 2.0 \
  --query "IntegrationId" --output text)

echo "Criando rotas..."
aws apigatewayv2 create-route --region $REGION --api-id $API_ID \
  --route-key "ANY /items" --target integrations/$INT_ITEMS
aws apigatewayv2 create-route --region $REGION --api-id $API_ID \
  --route-key "ANY /items/{proxy+}" --target integrations/$INT_PROXY
aws apigatewayv2 create-route --region $REGION --api-id $API_ID \
  --route-key "PUT /items/{proxy+}" --target integrations/$INT_PROXY
aws apigatewayv2 create-route --region $REGION --api-id $API_ID \
  --route-key "DELETE /items/{proxy+}" --target integrations/$INT_PROXY
aws apigatewayv2 create-route --region $REGION --api-id $API_ID \
  --route-key "GET /report" --target integrations/$INT_LAMBDA

echo "Adicionando permissao Lambda..."
aws lambda add-permission \
  --region $REGION \
  --function-name report-filmes \
  --statement-id apigateway-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*/report"

echo "Criando stage prod..."
aws apigatewayv2 create-stage \
  --region $REGION --api-id $API_ID \
  --stage-name prod --auto-deploy

echo ""
echo "=============================================="
echo "  INFRAESTRUTURA PROVISIONADA COM SUCESSO!"
echo "=============================================="
echo ""
echo "Frontend: http://catalogo-filmes-frontend-$ACCOUNT_ID.s3-website-$REGION.amazonaws.com"
echo "API:      https://$API_ID.execute-api.$REGION.amazonaws.com/prod"
