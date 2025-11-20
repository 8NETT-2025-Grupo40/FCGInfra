#!/usr/bin/env pwsh
# ============================================
# SETUP COMPLETO EKS CLUSTER COM EKSCTL
# Conta: 478511033947
# Região: us-east-1
# ============================================

param(
    [switch]$SkipClusterCreation = $false,
    [switch]$SkipAddons = $false,
    [switch]$SkipApp = $false
)

# Configurar AWS Profile
$env:AWS_PROFILE = "local"
$ErrorActionPreference = "Stop"

# Função auxiliar para Retry
function Invoke-WithRetry {
    param (
        [string]$Description,
        [ScriptBlock]$Command,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 10
    )

    $attempt = 1
    while ($attempt -le $MaxAttempts) {
        try {
            & $Command
            return
        } catch {
            if ($attempt -eq $MaxAttempts) {
                throw $_
            }
            Write-Host "[WARN]  Erro em '$Description'. Tentativa $attempt de $MaxAttempts. Aguardando ${DelaySeconds}s..." -ForegroundColor Yellow
            Write-Host "   Erro: $($_.Exception.Message)" -ForegroundColor Gray
            Start-Sleep -Seconds $DelaySeconds
            $attempt++
        }
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "    SETUP EKS CLUSTER - FCG" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ============================================
# FASE 1: CRIAR CLUSTER BASE
# ============================================
if (-not $SkipClusterCreation) {
    Write-Host "[1/4] Criando cluster EKS..." -ForegroundColor Yellow
    Write-Host "  > Isso levará ~15-20 minutos" -ForegroundColor Gray
    
    eksctl create cluster -f infrastructure/eks/cluster-config.yaml
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Erro ao criar cluster!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[OK] Cluster criado com sucesso!`n" -ForegroundColor Green
    
    # Atualizar kubeconfig (garantir)
    aws eks update-kubeconfig --region us-east-1 --name fcg
    
    # Verificar nodes
    Write-Host "Verificando nodes..." -ForegroundColor Gray
    kubectl get nodes
    
} else {
    Write-Host "[1/4] Pulando criação do cluster (já existe)`n" -ForegroundColor Gray
}

# ============================================
# FASE 2: CRIAR IAM SERVICE ACCOUNTS (IRSA)
# ============================================
Write-Host "[2/4] Configurando IRSA..." -ForegroundColor Yellow

# Criar namespace fcg primeiro
Write-Host "  > Criando namespaces..." -ForegroundColor Gray
kubectl create namespace fcg --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -

# IRSA para AWS Load Balancer Controller
Write-Host "  > Criando IRSA para Load Balancer Controller..." -ForegroundColor Gray
eksctl create iamserviceaccount `
  --cluster=fcg `
  --namespace=kube-system `
  --name=aws-load-balancer-controller `
  --attach-policy-arn=arn:aws:iam::478511033947:policy/AWSLoadBalancerControllerIAMPolicy `
  --approve `
  --override-existing-serviceaccounts `
  --region=us-east-1

# IRSA para External Secrets
Write-Host "  > Criando IRSA para External Secrets..." -ForegroundColor Gray
eksctl create iamserviceaccount `
  --cluster=fcg `
  --namespace=fcg `
  --name=fcg-user-api-fcg-user-api `
  --attach-policy-arn=arn:aws:iam::478511033947:policy/FCGExternalSecretsPolicy `
  --approve `
  --override-existing-serviceaccounts `
  --region=us-east-1

Write-Host "[OK] IRSA configurado!`n" -ForegroundColor Green

# ============================================
# FASE 3: INSTALAR ADD-ONS
# ============================================
if (-not $SkipAddons) {
    Write-Host "[3/4] Instalando add-ons..." -ForegroundColor Yellow
    
    # Adicionar repositórios Helm
    Write-Host "  > Atualizando repositórios Helm..." -ForegroundColor Gray
    Invoke-WithRetry -Description "Atualizar repositórios Helm" -Command {
        helm repo add eks https://aws.github.io/eks-charts
        helm repo add external-secrets https://charts.external-secrets.io
        helm repo update
    }
    
    # Instalar AWS Load Balancer Controller
    Write-Host "  > Instalando AWS Load Balancer Controller..." -ForegroundColor Gray
    $VPC_ID = aws eks describe-cluster --name fcg --region us-east-1 --query 'cluster.resourcesVpcConfig.vpcId' --output text
    
    Invoke-WithRetry -Description "Instalar AWS Load Balancer Controller" -Command {
        helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller `
          -n kube-system `
          --set clusterName=fcg `
          --set serviceAccount.create=false `
          --set serviceAccount.name=aws-load-balancer-controller `
          --set region=us-east-1 `
          --set vpcId=$VPC_ID `
          --wait
    }
    
    # Instalar External Secrets Operator
    Write-Host "  > Instalando External Secrets Operator..." -ForegroundColor Gray
    Invoke-WithRetry -Description "Instalar External Secrets Operator" -Command {
        helm upgrade --install external-secrets external-secrets/external-secrets `
          -n external-secrets `
          --set installCRDs=true `
          --wait
    }
    
    Write-Host "[OK] Add-ons instalados!`n" -ForegroundColor Green
    
} else {
    Write-Host "[3/4] Pulando instalação de add-ons`n" -ForegroundColor Gray
}

# ============================================
# FASE 4: DEPLOY DA APLICAÇÃO
# ============================================
if (-not $SkipApp) {
    Write-Host "[4/4] Fazendo deploy da aplicação..." -ForegroundColor Yellow
    
    # Verificar se values.yaml está configurado corretamente
    Write-Host "  > Verificando configuração do Helm chart..." -ForegroundColor Gray
    $valuesContent = Get-Content -Path "infrastructure/charts/values.yaml" -Raw
    
    if ($valuesContent -match "create:\s*true") {
        Write-Host "`n[WARN]  ATENÇÃO! infrastructure/charts/values.yaml precisa ser atualizado!" -ForegroundColor Red
        Write-Host "   serviceAccount.create deve ser 'false' (eksctl já criou)" -ForegroundColor Red
        Write-Host "`n   Execute: " -ForegroundColor Yellow
        Write-Host "   1. Abra infrastructure/charts/values.yaml" -ForegroundColor Yellow
        Write-Host "   2. Mude serviceAccount.create para false" -ForegroundColor Yellow
        Write-Host "   3. Mude serviceAccount.name para 'fcg-user-api-fcg-user-api'" -ForegroundColor Yellow
        Write-Host "   4. Remova serviceAccount.annotations`n" -ForegroundColor Yellow
        
        $response = Read-Host "Deseja continuar assim mesmo? (y/N)"
        if ($response -ne "y") {
            Write-Host "[ERROR] Deploy cancelado. Corrija values.yaml e execute novamente." -ForegroundColor Red
            exit 1
        }
    }
    
    # Deploy via Helm
    Write-Host "  > Fazendo deploy via Helm..." -ForegroundColor Gray
    Invoke-WithRetry -Description "Deploy da aplicação" -Command {
        helm upgrade --install fcg-user-api ./infrastructure/charts `
          --namespace fcg `
          -f infrastructure/charts/values.yaml `
          --wait `
          --timeout 5m
    }
    
    Write-Host "  > Aguardando provisionamento do ALB..." -ForegroundColor Gray
    Start-Sleep -Seconds 60
    
    # Verificar status
    Write-Host "`n[STATUS] Status do Deployment:" -ForegroundColor Cyan
    kubectl get pods -n fcg
    kubectl get externalsecret -n fcg
    kubectl get ingress -n fcg
    
    # Obter URL do ALB
    Write-Host "`n[LINK] Obtendo URL do ALB..." -ForegroundColor Cyan
    $ALB_URL = kubectl get ingress -n fcg fcg-user-api-fcg-user-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    
    if ($ALB_URL) {
        Write-Host "`n[OK] SETUP COMPLETO!" -ForegroundColor Green
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
        Write-Host "ALB URL: http://$ALB_URL" -ForegroundColor Yellow
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Green
        
        Write-Host "Testando health endpoint..." -ForegroundColor Gray
        Start-Sleep -Seconds 10
        try {
            $health = Invoke-WebRequest -Uri "http://$ALB_URL/health" -UseBasicParsing
            Write-Host "[OK] Health check: $($health.StatusCode) OK" -ForegroundColor Green
            Write-Host "   Response: $($health.Content)" -ForegroundColor Gray
        } catch {
            Write-Host "[WARN]  Health check falhou (ALB ainda provisionando)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[WARN]  ALB ainda sendo provisionado. Execute:" -ForegroundColor Yellow
        Write-Host "   kubectl get ingress -n fcg -w" -ForegroundColor Gray
    }
    
} else {
    Write-Host "[4/4] Pulando deploy da aplicação`n" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "         SETUP FINALIZADO" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "[INFO] Comandos úteis:" -ForegroundColor Cyan
Write-Host "  • Ver pods:     kubectl get pods -n fcg" -ForegroundColor Gray
Write-Host "  • Ver ingress:  kubectl get ingress -n fcg" -ForegroundColor Gray
Write-Host "  • Ver secrets:  kubectl get externalsecret -n fcg" -ForegroundColor Gray
Write-Host "  • Logs da app:  kubectl logs -n fcg -l app.kubernetes.io/name=fcg-user-api" -ForegroundColor Gray
Write-Host "  • Deletar tudo: ./infrastructure/eks/delete.ps1`n" -ForegroundColor Gray

