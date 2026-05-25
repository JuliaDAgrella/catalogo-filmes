@echo off
echo ================================================
echo   Catalogo de Filmes - Iniciar Projeto
echo ================================================
echo.
echo Abra o laboratorio, clique em AWS Details e Show
echo Cole cada credencial quando solicitado:
echo.

set /p ACCESS_KEY=aws_access_key_id: 
set /p SECRET_KEY=aws_secret_access_key: 
set /p SESSION_TOKEN=aws_session_token: 

echo.
echo [1/4] Configurando credenciais...
aws configure set aws_access_key_id %ACCESS_KEY%
aws configure set aws_secret_access_key %SECRET_KEY%
aws configure set aws_session_token %SESSION_TOKEN%
aws configure set region us-east-1

aws sts get-caller-identity > nul 2>&1
if %errorlevel% neq 0 (
    echo ERRO: Credenciais invalidas!
    pause
    exit /b 1
)
echo Credenciais OK!

echo.
echo [2/4] Buscando IP do backend...
for /f "tokens=*" %%i in ('aws ecs list-tasks --region us-east-1 --cluster catalogo-filmes-cluster --service-name backend-service --query "taskArns[0]" --output text') do set TASK_ARN=%%i
for /f "tokens=*" %%i in ('aws ecs describe-tasks --region us-east-1 --cluster catalogo-filmes-cluster --tasks %TASK_ARN% --query tasks[0].attachments[0].details[1].value --output text') do set ENI=%%i
for /f "tokens=*" %%i in ('aws ec2 describe-network-interfaces --region us-east-1 --network-interface-ids %ENI% --query "NetworkInterfaces[0].Association.PublicIp" --output text') do set BACKEND_IP=%%i

echo IP do backend: %BACKEND_IP%

echo.
echo [3/4] Atualizando API Gateway e Lambda com novo IP...
aws apigatewayv2 update-integration --region us-east-1 --api-id dyt0vjwv91 --integration-id kw607qh --integration-uri http://%BACKEND_IP%:3000/items > nul
aws apigatewayv2 update-integration --region us-east-1 --api-id dyt0vjwv91 --integration-id jio4ukk --integration-uri http://%BACKEND_IP%:3000/items/{proxy} > nul
aws lambda update-function-configuration --region us-east-1 --function-name report-filmes --environment Variables={BACKEND_URL=http://%BACKEND_IP%:3000} > nul
echo API Gateway e Lambda atualizados!

echo.
echo [4/4] Verificando backend...
timeout /t 5 /nobreak > nul
curl -s http://%BACKEND_IP%:3000/health > nul 2>&1
if %errorlevel% neq 0 (
    echo AVISO: Backend ainda inicializando, aguarde 1 minuto e acesse o frontend.
) else (
    echo Backend OK!
)

echo.
echo ================================================
echo   PROJETO PRONTO!
echo ================================================
echo.
echo Frontend: http://catalogo-filmes-frontend-078433732491.s3-website-us-east-1.amazonaws.com
echo API:      https://dyt0vjwv91.execute-api.us-east-1.amazonaws.com/prod/items
echo Relatorio:https://dyt0vjwv91.execute-api.us-east-1.amazonaws.com/prod/report
echo.
pause
