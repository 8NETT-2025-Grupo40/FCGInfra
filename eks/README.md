# Setup EKS com eksctl - Guia Rápido

> Setup simplificado do cluster EKS usando eksctl

## Pré-requisitos

Antes de começar, você precisa ter:

- **AWS CLI** configurado com profile "local"
- **eksctl** instalado ([instruções](https://eksctl.io/installation/))
- **kubectl** instalado
- **Helm 3** instalado
- **IAM Policies** já criadas:
  - `AWSLoadBalancerControllerIAMPolicy`
  - `FCGExternalSecretsPolicy`
- **AWS Secrets Manager** com secrets:
  - `fcg-api-user-connection-string`
  - `fcg-jwt-config`

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

## Setup Completo (Um Comando)

```powershell
# Executar setup completo
./infrastructure/eks/setup.ps1
```

**Tempo estimado:** 22-31 minutos (maioria passivo - aguardando AWS)

### O que o script faz:

1. Cria cluster EKS com Kubernetes 1.34
2. Configura OIDC provider automaticamente
3. Cria node group com 2x t3a.small
4. Configura access entries para AndersonMori
5. Cria IAM Service Accounts (IRSA) para:
   - AWS Load Balancer Controller
   - External Secrets Operator
6. Instala add-ons via Helm (com retry automático):
   - AWS Load Balancer Controller
   - External Secrets Operator
7. Faz deploy da aplicação FCG User API
8. Provisiona ALB e testa health endpoint

---

## Estrutura de Arquivos

```
FCGUserApi/
├── infrastructure/
│   ├── eks/
│   │   ├── cluster-config.yaml   # Configuração do cluster eksctl
│   │   ├── setup.ps1             # Script de setup completo
│   │   ├── delete.ps1            # Script de limpeza
│   │   ├── validate.ps1          # Validação de pré-requisitos
│   │   └── README.md             # Este arquivo
│   ├── charts/
│   │   ├── Chart.yaml
│   │   ├── values.yaml           # ATUALIZADO (serviceAccount.create: false)
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── ingress.yaml
│   │       ├── serviceaccount.yaml
│   │       ├── secretstore.yaml
│   │       └── externalsecret.yaml
│   └── iam/
│       ├── alb-controller-policy.json
│       └── external-secrets-policy.json
└── src/                          # Código fonte da aplicação
```

---

## Validação de Pré-requisitos

Antes de executar o setup, você pode validar se o ambiente está configurado:

```powershell
./infrastructure/eks/validate.ps1
```

O script verifica:
- AWS CLI, eksctl, kubectl, Helm instalados
- Credenciais AWS válidas
- IAM Policies existentes
- AWS Secrets Manager configurado
- Arquivos de configuração presentes

---

## Execução por Fases (Troubleshooting)

Se algo falhar, você pode executar por fases:

```powershell
# Pular criação do cluster (se já existe)
./infrastructure/eks/setup.ps1 -SkipClusterCreation

# Pular add-ons (se já instalados)
./infrastructure/eks/setup.ps1 -SkipAddons

# Pular aplicação (só subir infraestrutura)
./infrastructure/eks/setup.ps1 -SkipApp
```

---

## Deletar o Cluster

```powershell
./infrastructure/eks/delete.ps1
```

Digite `DELETE` para confirmar. Isso remove:
- Aplicação (Helm release)
- Add-ons (External Secrets, Load Balancer Controller)
- Cluster EKS
- Node groups
- IAM Service Accounts (roles com OIDC)
- OIDC Provider

**Recursos que PERMANECEM:**
- IAM Policies (AWSLoadBalancerControllerIAMPolicy, FCGExternalSecretsPolicy)
- AWS Secrets Manager (fcg-api-user-connection-string, fcg-jwt-config)
- VPC (vpc-0e6d1df089da1ec39)

---

## Verificação Pós-Setup

```powershell
# Ver nodes
kubectl get nodes

# Ver pods da aplicação
kubectl get pods -n fcg

# Ver External Secrets
kubectl get externalsecret -n fcg

# Ver Ingress/ALB
kubectl get ingress -n fcg

# Testar aplicação
$ALB_URL = kubectl get ingress -n fcg fcg-user-api-fcg-user-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
curl "http://$ALB_URL/health"
```

---

## Troubleshooting

### Pods em CreateContainerConfigError

**Causa:** External Secret não sincronizou.

```powershell
# Verificar External Secret
kubectl describe externalsecret -n fcg

# Verificar logs do External Secrets Operator
kubectl logs -n external-secrets deployment/external-secrets
```

### ALB não provisiona

**Causa:** Load Balancer Controller com erro.

```powershell
# Ver logs do controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Ver status do ingress
kubectl describe ingress -n fcg
```

### Erro "serviceaccount already exists"

**Causa:** values.yaml ainda tem `create: true`.

**Solução:** Editar `infrastructure/charts/values.yaml`:
```yaml
serviceAccount:
  create: false  # ← Mudar para false
  name: "fcg-user-api-fcg-user-api"
```

---

## Diferenças: Setup Manual vs eksctl

| Aspecto | Setup Manual | Setup eksctl |
|---------|--------------|--------------|
| Comandos | ~50 comandos | 1 script |
| Tempo ativo | ~30 min | ~5 min |
| OIDC/IRSA | Manual (propenso a erro) | Automático |
| Roles IAM | Customizadas | Geradas pelo eksctl |
| Reprodutibilidade | Baixa | Alta (YAML versionado) |
| Troubleshooting | Difícil | Mais fácil |

---

## Configurações do Cluster

**Cluster:**
- Nome: `fcg`
- Região: `us-east-1`
- Kubernetes: `1.34`
- VPC: `vpc-0e6d1df089da1ec39`

**Node Group:**
- Nome: `low-cost`
- Tipo: `t3a.small`
- Quantidade: 2 (min) - 3 (max)
- Subnets: us-east-1a, us-east-1b

**Add-ons:**
- AWS Load Balancer Controller (via Helm)
- External Secrets Operator (via Helm)

---

## Links Úteis

- [eksctl Documentation](https://eksctl.io/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [External Secrets Operator](https://external-secrets.io/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)

---

## Dicas

1. **Sempre use o profile "local":** O script já configura `$env:AWS_PROFILE = "local"`
2. **Commit do cluster-config.yaml:** Versione no Git para rastreabilidade
3. **Não delete as IAM Policies:** São reutilizáveis entre clusters
4. **Aguarde o ALB:** Leva 2-3 minutos após o deploy para ficar ativo
5. **Use -SkipClusterCreation:** Para reinstalar apenas add-ons/app
6. **Retry Automático:** O script tenta até 3 vezes em caso de falhas de rede
7. **Valide antes de executar:** Use `validate.ps1` para verificar pré-requisitos

---

## Próximos Passos

Após o setup bem-sucedido:

1. Configurar CI/CD (GitHub Actions)
2. Configurar monitoramento (CloudWatch, Prometheus)
3. Configurar domínio customizado (Route 53)
4. Habilitar HTTPS (ACM + ALB)
5. Configurar autoscaling (HPA, Cluster Autoscaler)

---

**Criado em:** 18 de Novembro de 2025  
**Versão:** 1.0  
**Account ID:** 478511033947
