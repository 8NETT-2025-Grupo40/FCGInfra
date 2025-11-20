#!/usr/bin/env pwsh
# ============================================
# VALIDAÇÃO PRÉ-SETUP
# Verifica se tudo está pronto antes do setup
# ============================================

$env:AWS_PROFILE = "local"
$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "    VALIDAÇÃO PRÉ-SETUP" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$errorsList = @()
$warningsList = @()

# 1. Verificar AWS CLI
Write-Host "[1/8] Verificando AWS CLI..." -ForegroundColor Yellow
try {
    $awsVersion = aws --version 2>&1
    Write-Host "  [OK] AWS CLI instalado: $awsVersion" -ForegroundColor Green
} catch {
    $errorsList += "AWS CLI não encontrado"
    Write-Host "  [ERROR] AWS CLI não encontrado" -ForegroundColor Red
}

# 2. Verificar eksctl
Write-Host "[2/8] Verificando eksctl..." -ForegroundColor Yellow
try {
    $eksctlVersion = eksctl version
    Write-Host "  [OK] eksctl instalado: $eksctlVersion" -ForegroundColor Green
} catch {
    $errorsList += "eksctl não encontrado. Instale: choco install eksctl"
    Write-Host "  [ERROR] eksctl não encontrado" -ForegroundColor Red
}

# 3. Verificar kubectl
Write-Host "[3/8] Verificando kubectl..." -ForegroundColor Yellow
try {
    $null = kubectl version --client --short 2>&1
    Write-Host "  [OK] kubectl instalado" -ForegroundColor Green
} catch {
    $errorsList += "kubectl não encontrado"
    Write-Host "  [ERROR] kubectl não encontrado" -ForegroundColor Red
}

# 4. Verificar Helm
Write-Host "[4/8] Verificando Helm..." -ForegroundColor Yellow
try {
    $helmVersion = helm version --short
    Write-Host "  [OK] Helm instalado: $helmVersion" -ForegroundColor Green
} catch {
    $errorsList += "Helm não encontrado"
    Write-Host "  [ERROR] Helm não encontrado" -ForegroundColor Red
}

# 5. Verificar AWS credentials
Write-Host "[5/8] Verificando credenciais AWS..." -ForegroundColor Yellow
try {
    $identity = aws sts get-caller-identity 2>&1 | ConvertFrom-Json
    if ($identity.Account -eq "478511033947") {
        Write-Host "  [OK] Credenciais válidas: $($identity.Arn)" -ForegroundColor Green
    } else {
        $warningsList += "Account ID diferente: $($identity.Account) (esperado: 478511033947)"
        Write-Host "  [WARN]  Account ID: $($identity.Account)" -ForegroundColor Yellow
    }
} catch {
    $errorsList += "Não foi possível verificar credenciais AWS"
    Write-Host "  [ERROR] Erro ao verificar credenciais" -ForegroundColor Red
}

# 6. Verificar IAM Policies
Write-Host "[6/8] Verificando IAM Policies..." -ForegroundColor Yellow
try {
    $null = aws iam get-policy --policy-arn arn:aws:iam::478511033947:policy/AWSLoadBalancerControllerIAMPolicy 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] AWSLoadBalancerControllerIAMPolicy existe" -ForegroundColor Green
    } else {
        $errorsList += "AWSLoadBalancerControllerIAMPolicy não encontrada"
        Write-Host "  [ERROR] AWSLoadBalancerControllerIAMPolicy não encontrada" -ForegroundColor Red
    }
    
    $null = aws iam get-policy --policy-arn arn:aws:iam::478511033947:policy/FCGExternalSecretsPolicy 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] FCGExternalSecretsPolicy existe" -ForegroundColor Green
    } else {
        $warningsList += "FCGExternalSecretsPolicy não encontrada (será criada se necessário)"
        Write-Host "  [WARN]  FCGExternalSecretsPolicy não encontrada" -ForegroundColor Yellow
    }
} catch {
    $warningsList += "Não foi possível verificar IAM Policies"
    Write-Host "  [WARN]  Erro ao verificar policies" -ForegroundColor Yellow
}

# 7. Verificar AWS Secrets
Write-Host "[7/8] Verificando AWS Secrets Manager..." -ForegroundColor Yellow
try {
    $null = aws secretsmanager describe-secret --secret-id fcg-api-user-connection-string --region us-east-1 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] fcg-api-user-connection-string existe" -ForegroundColor Green
    } else {
        $warningsList += "fcg-api-user-connection-string não encontrado"
        Write-Host "  [WARN]  fcg-api-user-connection-string não encontrado" -ForegroundColor Yellow
    }
    
    $null = aws secretsmanager describe-secret --secret-id fcg-jwt-config --region us-east-1 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] fcg-jwt-config existe" -ForegroundColor Green
    } else {
        $warningsList += "fcg-jwt-config não encontrado"
        Write-Host "  [WARN]  fcg-jwt-config não encontrado" -ForegroundColor Yellow
    }
} catch {
    $warningsList += "Não foi possível verificar secrets"
    Write-Host "  [WARN]  Erro ao verificar secrets" -ForegroundColor Yellow
}

# 8. Verificar arquivos necessários
Write-Host "[8/8] Verificando arquivos locais..." -ForegroundColor Yellow
$requiredFiles = @(
    "infrastructure/eks/cluster-config.yaml",
    "infrastructure/eks/setup.ps1",
    "infrastructure/eks/delete.ps1",
    "infrastructure/charts/values.yaml"
)

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "  [OK] $file" -ForegroundColor Green
    } else {
        $errorsList += "Arquivo não encontrado: $file"
        Write-Host "  [ERROR] $file não encontrado" -ForegroundColor Red
    }
}

# Verificar configuração do values.yaml
$valuesContent = Get-Content -Path "infrastructure/charts/values.yaml" -Raw
if ($valuesContent -match "serviceAccount:\s+create:\s*false") {
    Write-Host "  [OK] values.yaml configurado corretamente (serviceAccount.create: false)" -ForegroundColor Green
} else {
    $errorsList += "infrastructure/charts/values.yaml precisa ser atualizado: serviceAccount.create deve ser false"
    Write-Host "  [ERROR] values.yaml não atualizado (serviceAccount.create deve ser false)" -ForegroundColor Red
}

# Resumo
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "         RESUMO DA VALIDAÇÃO" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($errorsList.Count -eq 0 -and $warningsList.Count -eq 0) {
    Write-Host "[OK] TUDO OK! Você está pronto para executar o setup." -ForegroundColor Green
    Write-Host "`nExecute: ./infrastructure/eks/setup.ps1`n" -ForegroundColor Yellow
    exit 0
} elseif ($errorsList.Count -eq 0) {
    Write-Host "[WARN]  AVISOS ($($warningsList.Count)):" -ForegroundColor Yellow
    foreach ($warn in $warningsList) {
        Write-Host "  • $warn" -ForegroundColor Yellow
    }
    Write-Host "`nVocê pode continuar, mas revise os avisos acima." -ForegroundColor Yellow
    Write-Host "Execute: ./infrastructure/eks/setup.ps1`n" -ForegroundColor Gray
    exit 0
} else {
    Write-Host "[ERROR] ERROS ENCONTRADOS ($($errorsList.Count)):" -ForegroundColor Red
    foreach ($err in $errorsList) {
        Write-Host "  • $err" -ForegroundColor Red
    }
    
    if ($warningsList.Count -gt 0) {
        Write-Host "`n[WARN]  AVISOS ($($warningsList.Count)):" -ForegroundColor Yellow
        foreach ($warn in $warningsList) {
            Write-Host "  • $warn" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`nCorrija os erros antes de continuar.`n" -ForegroundColor Red
    exit 1
}

