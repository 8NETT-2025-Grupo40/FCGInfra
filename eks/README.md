# FCGInfra - Setup do Cluster EKS

> Repositório de infraestrutura compartilhada para gerenciar o cluster EKS e add-ons comuns

## Visão Geral

Este repositório gerencia a infraestrutura EKS compartilhada para todas as APIs FCG. É responsável por:

- Criar e configurar o cluster EKS
- Instalar add-ons compartilhados (AWS Load Balancer Controller, External Secrets Operator)
- Gerenciar políticas IAM e configurações IRSA
- Criar namespaces compartilhados

**IMPORTANTE:** Este repositório NÃO faz deploy de aplicações. Cada repositório de API (FCGUserApi, FCGPaymentApi, etc.) gerencia seu próprio deployment.

## Pré-requisitos

Antes de executar o setup, certifique-se de ter:

- **AWS CLI** configurado com credenciais apropriadas
- **eksctl** instalado ([guia de instalação](https://eksctl.io/installation/))
- **kubectl** instalado
- **Helm 3** instalado
- **AWS Account ID:** 478511033947
- **Políticas IAM** criadas na AWS (podem ser criadas pelo script de setup):
  - `AWSLoadBalancerControllerIAMPolicy`
  - `FCGExternalSecretsPolicy`

### Instalar eksctl (Windows)

```powershell
# Via Chocolatey
choco install eksctl

# Via Scoop
scoop install eksctl

# Verificar instalação
eksctl version
```

---

## Métodos de Setup

### Opção 1: GitHub Actions (Recomendado para Produção)

1. Acesse GitHub Actions: `https://github.com/8NETT-2025-Grupo40/FCGInfra/actions`
2. Selecione o workflow: **"Setup EKS Cluster & Add-ons"**
3. Clique em **"Run workflow"**
4. Configure as opções:
   - `skip_cluster`: Marque se o cluster já existe
   - `skip_addons`: Marque se os add-ons já estão instalados
5. Clique em **"Run workflow"**

**Tempo estimado:** 20-25 minutos

### Opção 2: Script PowerShell (Desenvolvimento Local)

```powershell
# Setup completo
./eks/setup.ps1

# Pular criação do cluster (se já existe)
./eks/setup.ps1 -SkipClusterCreation

# Pular instalação de add-ons (se já instalados)
./eks/setup.ps1 -SkipAddons
```

**Tempo estimado:** 20-25 minutos (maior parte aguardando recursos da AWS)

---

## O Que é Criado

### Componentes de Infraestrutura

1. **Cluster EKS**
   - Nome: `fcg`
   - Região: `us-east-1`
   - Versão Kubernetes: 1.34
   - VPC: `vpc-0e6d1df089da1ec39` (existente)
   - OIDC provider habilitado

2. **Node Group**
   - Nome: `low-cost`
   - Tipo de instância: `t3a.small`
   - Capacidade desejada: 2 nodes
   - Mín: 2, Máx: 3
   - Zonas de disponibilidade: us-east-1a, us-east-1b

3. **Namespaces**
   - `fcg` (para deployments de aplicações)
   - `external-secrets` (para External Secrets Operator)

4. **Políticas IAM** (se não existirem)
   - `AWSLoadBalancerControllerIAMPolicy`
   - `FCGExternalSecretsPolicy`

5. **IRSA (IAM Roles for Service Accounts)**
   - Service account do AWS Load Balancer Controller
   - Vinculado à AWSLoadBalancerControllerIAMPolicy

6. **Add-ons Helm**
   - AWS Load Balancer Controller (namespace kube-system)
   - External Secrets Operator (namespace external-secrets)

---

## Estrutura do Repositório

```
FCGInfra/
├── .github/
│   └── workflows/
│       ├── cluster-setup.yml     # Workflow GitHub Actions para criação do cluster
│       └── cluster-destroy.yml   # Workflow GitHub Actions para deleção do cluster
├── eks/
│   ├── cluster-config.yaml       # Configuração do cluster eksctl
│   ├── setup.ps1                 # Script PowerShell de setup
│   ├── delete.ps1                # Script PowerShell de limpeza
│   ├── validate.ps1              # Script de validação de pré-requisitos
│   └── README.md                 # Este arquivo
├── iam/
│   ├── alb-controller-policy.json        # Política IAM para ALB Controller
│   └── external-secrets-policy.json      # Política IAM para External Secrets
└── README.md                     # Documentação principal do repositório
```

---

## Validação de Pré-requisitos

Antes de executar o setup, valide seu ambiente:

```powershell
./eks/validate.ps1
```

O script verifica:
- Ferramentas necessárias instaladas (AWS CLI, eksctl, kubectl, Helm)
- Validade das credenciais AWS
- Existência das políticas IAM (opcional)
- Presença dos arquivos de configuração

---

## Verificação Após Setup

Após o setup bem-sucedido, verifique a instalação:

```powershell
# Verificar nodes do cluster
kubectl get nodes

# Verificar AWS Load Balancer Controller
kubectl get deployment -n kube-system aws-load-balancer-controller

# Verificar External Secrets Operator
kubectl get deployment -n external-secrets external-secrets

# Verificar namespaces
kubectl get namespace fcg
kubectl get namespace external-secrets

# Verificar ausência de recursos de aplicação (esperado)
kubectl get all -n fcg
# No resources found in fcg namespace.
```

**Nota:** Neste ponto, NÃO deve haver recursos Ingress ou ALB. Estes serão criados pelos deployments individuais das APIs.

---

## Deleção do Cluster

### Opção 1: GitHub Actions

1. Acesse: `https://github.com/8NETT-2025-Grupo40/FCGInfra/actions`
2. Selecione o workflow: **"Destroy EKS Cluster"**
3. Clique em **"Run workflow"**
4. Digite **"DESTROY"** no campo de confirmação
5. Clique em **"Run workflow"**

### Opção 2: Script PowerShell

```powershell
./eks/delete.ps1
```

Digite `DELETE` para confirmar.

### O Que é Deletado

- Cluster EKS e node groups
- IAM Service Accounts (roles IRSA)
- OIDC Provider
- Helm releases (Load Balancer Controller, External Secrets Operator)
- Application Load Balancers (se existirem)
- Target Groups

### O Que Permanece

Os seguintes recursos NÃO são deletados e devem ser gerenciados manualmente:

- Políticas IAM (`AWSLoadBalancerControllerIAMPolicy`, `FCGExternalSecretsPolicy`)
- VPC e networking (`vpc-0e6d1df089da1ec39`)
- Secrets do AWS Secrets Manager
- Repositórios ECR

---

## Troubleshooting

### Load Balancer Controller Não Está Executando

**Verificar status do deployment:**
```powershell
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

**Causas comuns:**
- IRSA não configurado corretamente
- Política IAM ausente ou incorreta
- VPC ID incompatível

### External Secrets Operator Não Está Executando

**Verificar status do deployment:**
```powershell
kubectl get deployment -n external-secrets external-secrets
kubectl logs -n external-secrets deployment/external-secrets
```

**Causas comuns:**
- CRDs não instalados
- Namespace não criado
- Timeout na instalação do Helm

### Falha na Criação do Cluster

**Verificar logs do eksctl:**
```powershell
eksctl utils describe-stacks --region us-east-1 --cluster fcg
```

**Causas comuns:**
- IDs de VPC ou subnet incorretos
- Permissões IAM insuficientes
- Limites de recursos na conta AWS
- Versão do Kubernetes não suportada pelo EKS

### Falha na Criação do IRSA

**Verificar se o OIDC provider existe:**
```powershell
aws eks describe-cluster --name fcg --region us-east-1 --query 'cluster.identity.oidc.issuer'
```

**Solução:** Re-executar com flag `--override-existing-serviceaccounts` (já incluída nos scripts)

---

## Configuração do Cluster

### Detalhes do Cluster
- **Nome:** `fcg`
- **Região:** `us-east-1`
- **Versão Kubernetes:** `1.34`
- **VPC ID:** `vpc-0e6d1df089da1ec39` (existente)
- **Modo de Autenticação:** `API_AND_CONFIG_MAP`

### Node Group
- **Nome:** `low-cost`
- **Tipo de Instância:** `t3a.small`
- **Capacidade Desejada:** 2 nodes
- **Tamanho Mínimo:** 2
- **Tamanho Máximo:** 3
- **Zonas de Disponibilidade:** us-east-1a, us-east-1b

### Add-ons
- **AWS Load Balancer Controller:** Instalado via Helm no namespace `kube-system`
- **External Secrets Operator:** Instalado via Helm no namespace `external-secrets`

---

## Integração com Repositórios de APIs

Cada repositório de API (FCGUserApi, FCGPaymentApi, etc.) deve:

1. **Criar seu próprio IRSA** para External Secrets:
   ```bash
   eksctl create iamserviceaccount \
     --cluster=fcg \
     --namespace=fcg \
     --name=<api-name>-sa \
     --attach-policy-arn=arn:aws:iam::478511033947:policy/FCGExternalSecretsPolicy \
     --approve \
     --region=us-east-1
   ```

2. **Usar ALB compartilhado** via annotation no Ingress:
   ```yaml
   metadata:
     annotations:
       alb.ingress.kubernetes.io/group.name: fcg
   ```

3. **Fazer deploy no namespace `fcg`:**
   ```bash
   helm upgrade --install <release-name> ./charts -n fcg
   ```

---

## Melhores Práticas

1. **Controle de Versão:** Sempre commit mudanças no `cluster-config.yaml` no Git
2. **Políticas IAM:** Mantenha as políticas IAM - elas são reutilizáveis em recriações do cluster
3. **Execução em Fases:** Use flags de skip (`-SkipClusterCreation`, `skip_cluster`) para atualizações parciais
4. **Validação Primeiro:** Execute `validate.ps1` antes do setup para identificar problemas de configuração antecipadamente
5. **Monitorar Recursos:** Verifique regularmente custos e utilização de recursos do cluster
6. **Documentação:** Atualize este README ao fazer mudanças na infraestrutura

---

## Referências

- [Documentação eksctl](https://eksctl.io/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [External Secrets Operator](https://external-secrets.io/)
- [Guia de Melhores Práticas EKS](https://aws.github.io/aws-eks-best-practices/)

---

**Última Atualização:** 20 de Novembro de 2025  
**AWS Account ID:** 478511033947  
**Repositório:** FCGInfra
