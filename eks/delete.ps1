#!/usr/bin/env pwsh
# ============================================
# DELETE EKS CLUSTER COM EKSCTL
# ============================================

param(
    [switch]$Force = $false
)

$env:AWS_PROFILE = "local"
$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Red
Write-Host "    DELETE EKS CLUSTER - FCG" -ForegroundColor Red
Write-Host "========================================`n" -ForegroundColor Red

if (-not $Force) {
    Write-Host "[WARN]  ATENÇÃO: Isso deletará o cluster fcg e todos os recursos!" -ForegroundColor Yellow
    $confirm = Read-Host "Digite 'DELETE' para confirmar"

    if ($confirm -ne "DELETE") {
        Write-Host "[ERROR] Cancelado." -ForegroundColor Gray
        exit 0
    }
} else {
    Write-Host "[WARN]  Modo FORCE ativado - deletando sem confirmação..." -ForegroundColor Yellow
}

# 1. Deletar aplicação
Write-Host "`n[1/3] Deletando aplicação..." -ForegroundColor Yellow
helm uninstall fcg-user-api -n fcg --ignore-not-found

Write-Host "  > Aguardando ALB ser deletado..." -ForegroundColor Gray
Start-Sleep -Seconds 90

# 2. Deletar add-ons
Write-Host "`n[2/3] Deletando add-ons..." -ForegroundColor Yellow
helm uninstall external-secrets -n external-secrets --ignore-not-found
helm uninstall aws-load-balancer-controller -n kube-system --ignore-not-found

Start-Sleep -Seconds 30

# 3. Deletar cluster (deleta tudo: nodes, IAM service accounts, OIDC, etc)
Write-Host "`n[3/3] Deletando cluster..." -ForegroundColor Yellow
Write-Host "  > Isso levará ~10-15 minutos" -ForegroundColor Gray

eksctl delete cluster --name fcg --region us-east-1 --wait

Write-Host "`n[OK] Cluster deletado com sucesso!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Green

Write-Host "[INFO] Recursos que PERMANECEM (não foram deletados):" -ForegroundColor Cyan
Write-Host "  • IAM Policy: AWSLoadBalancerControllerIAMPolicy" -ForegroundColor Gray
Write-Host "  • IAM Policy: FCGExternalSecretsPolicy" -ForegroundColor Gray
Write-Host "  • AWS Secrets: fcg-api-user-connection-string" -ForegroundColor Gray
Write-Host "  • AWS Secrets: fcg-jwt-config" -ForegroundColor Gray
Write-Host "  • VPC: vpc-0e6d1df089da1ec39`n" -ForegroundColor Gray

