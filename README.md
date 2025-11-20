# FCG Infrastructure - EKS Cluster & Shared Resources

This repository manages the **shared infrastructure** for the Fiap Cloud Games (FCG) platform, including the EKS cluster, add-ons, and common resources used by all API services.

## 📁 Repository Structure

```
fcg-infra/
├── .github/workflows/
│   ├── cluster-setup.yml      # Create/update EKS cluster
│   └── cluster-destroy.yml    # Destroy EKS cluster
├── eks/
│   ├── cluster-config.yaml    # eksctl cluster configuration
│   ├── setup.ps1              # Local setup script (PowerShell)
│   ├── delete.ps1             # Local deletion script
│   ├── validate.ps1           # Pre-flight validation
│   └── README.md              # EKS documentation
├── iam/
│   ├── alb-controller-policy.json        # IAM policy for ALB Controller
│   └── external-secrets-policy.json      # IAM policy for External Secrets
└── README.md                  # This file
```

## 🎯 Responsibilities

This repository is responsible for:

✅ **EKS Cluster Management**
- Create/delete the `fcg` cluster in `us-east-1`
- Manage node groups and scaling policies
- Configure OIDC provider for IRSA (IAM Roles for Service Accounts)

✅ **Shared Add-ons**
- AWS Load Balancer Controller (manages ALB for all Ingresses)
- External Secrets Operator (syncs secrets from AWS Secrets Manager)
- Future: Cluster Autoscaler, Metrics Server, etc.

✅ **IAM Policies**
- `AWSLoadBalancerControllerIAMPolicy`: For ALB management
- `FCGExternalSecretsPolicy`: For reading secrets from Secrets Manager

✅ **Namespaces**
- `fcg`: Main namespace for all API services
- `external-secrets`: For External Secrets Operator

❌ **NOT Responsible For**
- Application code (lives in individual API repos)
- Application-specific Helm charts (each API manages its own)
- Application-specific secrets values (managed by each API team)
- ECR repositories (each API creates/manages its own)

## 🚀 Usage

### Prerequisites

- AWS Account: `478511033947`
- AWS Region: `us-east-1`
- Existing VPC: `vpc-0e6d1df089da1ec39`
- GitHub Secrets configured:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`

### Option 1: GitHub Actions (Recommended)

#### Create/Update Cluster

1. Go to **Actions** → **Setup EKS Cluster & Add-ons**
2. Click **Run workflow**
3. Configure options:
   - `skip_cluster`: Check if cluster already exists
   - `skip_addons`: Check if add-ons already installed
4. Click **Run workflow** and monitor progress (~15-20 minutes)

#### Destroy Cluster

1. Go to **Actions** → **Destroy EKS Cluster**
2. Click **Run workflow**
3. Type **`DESTROY`** in the confirmation field
4. Click **Run workflow** and monitor progress (~10-15 minutes)

⚠️ **Warning**: This deletes the entire cluster and all deployments!

### Option 2: Local Setup (PowerShell)

#### Create Cluster

```powershell
# Full setup (cluster + add-ons)
./eks/setup.ps1

# Skip cluster creation (if already exists)
./eks/setup.ps1 -SkipClusterCreation

# Skip add-ons installation (if already installed)
./eks/setup.ps1 -SkipAddons

# Skip application deployment
./eks/setup.ps1 -SkipApp
```

#### Validate Prerequisites

```powershell
./eks/validate.ps1
```

#### Delete Cluster

```powershell
./eks/delete.ps1
```

## 🏗️ Cluster Configuration

### Cluster Details

- **Name**: `fcg`
- **Region**: `us-east-1`
- **Kubernetes Version**: `1.34`
- **Account ID**: `478511033947`
- **VPC**: `vpc-0e6d1df089da1ec39`
- **Authentication Mode**: `API_AND_CONFIG_MAP`

### Node Group

- **Name**: `low-cost`
- **Instance Type**: `t3a.small`
- **Desired Capacity**: 2 nodes
- **Min Size**: 2 nodes
- **Max Size**: 3 nodes
- **Availability Zones**: `us-east-1a`, `us-east-1b`

### Add-ons Installed

1. **AWS Load Balancer Controller** (`kube-system` namespace)
   - Manages ALB for Kubernetes Ingresses
   - ServiceAccount: `aws-load-balancer-controller`
   - IRSA attached to `AWSLoadBalancerControllerIAMPolicy`

2. **External Secrets Operator** (`external-secrets` namespace)
   - Syncs secrets from AWS Secrets Manager to Kubernetes
   - Each API creates its own SecretStore with IRSA

## 📝 API Service Integration

### What Each API Repository Must Do

Each API service (e.g., `FCGUserApi`, `FCGOrderApi`) is responsible for:

1. **Build and Push Docker Image to ECR**
   ```bash
   docker build -t <account>.dkr.ecr.us-east-1.amazonaws.com/<api-name>:latest .
   docker push <account>.dkr.ecr.us-east-1.amazonaws.com/<api-name>:latest
   ```

2. **Create IRSA (IAM Role for Service Account)**
   ```bash
   eksctl create iamserviceaccount \
     --cluster=fcg \
     --namespace=fcg \
     --name=<api-name>-sa \
     --attach-policy-arn=arn:aws:iam::478511033947:policy/FCGExternalSecretsPolicy \
     --approve \
     --override-existing-serviceaccounts \
     --region=us-east-1
   ```

3. **Deploy via Helm to `fcg` namespace**
   ```bash
   helm upgrade --install <api-name> ./k8s \
     --namespace fcg \
     --set image.tag=<version> \
     --wait
   ```

4. **Configure Ingress with Shared ALB**
   ```yaml
   annotations:
     alb.ingress.kubernetes.io/group.name: fcg  # Share ALB with other APIs
     alb.ingress.kubernetes.io/target-type: ip
   ```

### Prerequisites for API Deployment

Before deploying any API, ensure:

- ✅ EKS cluster `fcg` exists and is running
- ✅ Namespace `fcg` exists
- ✅ AWS Load Balancer Controller is installed
- ✅ External Secrets Operator is installed
- ✅ ECR repository for the API exists
- ✅ AWS Secrets Manager secrets are created (e.g., `fcg-api-<name>-connection-string`)

### Example: Deploy User API

See [FCGUserApi repository](https://github.com/8NETT-2025-Grupo40/FCGUserApi) for a complete example of:
- Helm chart structure (`k8s/` directory)
- GitHub Actions workflow for EKS deployment
- IRSA configuration for External Secrets

## 🔐 IAM Policies

### AWSLoadBalancerControllerIAMPolicy

**ARN**: `arn:aws:iam::478511033947:policy/AWSLoadBalancerControllerIAMPolicy`

**Purpose**: Allow ALB Controller to manage Application Load Balancers

**Attached To**: `aws-load-balancer-controller` ServiceAccount in `kube-system`

### FCGExternalSecretsPolicy

**ARN**: `arn:aws:iam::478511033947:policy/FCGExternalSecretsPolicy`

**Purpose**: Allow reading secrets from AWS Secrets Manager

**Permissions**:
- `secretsmanager:GetSecretValue`
- `secretsmanager:DescribeSecret`

**Resources**:
- `fcg-api-user-connection-string*`
- `fcg-jwt-config*`
- (Add more as needed for other APIs)

**Attached To**: Each API's ServiceAccount (created during API deployment)

## 🐛 Troubleshooting

### Cluster Not Creating

```bash
# Check eksctl version
eksctl version

# Validate cluster config
eksctl create cluster -f eks/cluster-config.yaml --dry-run

# Check AWS credentials
aws sts get-caller-identity
```

### ALB Not Provisioning

```bash
# Check ALB Controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Check Ingress status
kubectl describe ingress -n fcg <ingress-name>

# Verify ServiceAccount IRSA annotation
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml
```

### External Secrets Not Syncing

```bash
# Check External Secrets Operator logs
kubectl logs -n external-secrets deployment/external-secrets

# Check SecretStore status
kubectl get secretstore -n fcg
kubectl describe secretstore -n fcg <secretstore-name>

# Check ExternalSecret status
kubectl get externalsecret -n fcg
kubectl describe externalsecret -n fcg <externalsecret-name>
```

### Nodes Not Ready

```bash
# Check node status
kubectl get nodes

# Describe node
kubectl describe node <node-name>

# Check node group in eksctl
eksctl get nodegroup --cluster=fcg --region=us-east-1
```

## 📊 Monitoring & Maintenance

### Check Cluster Health

```bash
# Get cluster info
aws eks describe-cluster --name fcg --region us-east-1

# Check nodes
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system
kubectl get pods -n external-secrets

# Check all deployments in fcg namespace
kubectl get deployments -n fcg
```

### Update Add-ons

```bash
# Update Helm repos
helm repo update

# Upgrade ALB Controller
helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --reuse-values

# Upgrade External Secrets Operator
helm upgrade external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --reuse-values
```

## 🔗 Related Repositories

- [FCGUserApi](https://github.com/8NETT-2025-Grupo40/FCGUserApi) - User authentication API
- [FCGOrderApi](https://github.com/8NETT-2025-Grupo40/FCGOrderApi) - Order management API (example)

## 📚 Documentation

- [EKS Setup Guide](eks/README.md)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [External Secrets Operator](https://external-secrets.io/)
- [eksctl Documentation](https://eksctl.io/)

## 🤝 Contributing

This is shared infrastructure. Changes should be:
1. Discussed with the team
2. Tested in a non-production environment first
3. Deployed during maintenance windows
4. Communicated to all API teams

## 📞 Support

For issues with:
- **Cluster creation/deletion**: Check this repository's Issues
- **API deployments**: Check the respective API repository
- **AWS resources**: Contact DevOps team
