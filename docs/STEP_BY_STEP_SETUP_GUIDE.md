# End-to-End Setup & Deployment Guide

This guide walks through deploying the **Todo DevOps Project** from scratch on **AWS** using **Terraform (IaC)**, **GitHub Actions (CI/CD)**, **AWS OIDC**, **AWS ECR**, **AWS Lightsail**, **Docker Blue-Green Zero-Downtime Deployments**, and **Let's Encrypt SSL**.

---

## Table of Contents
1. [Prerequisites](#1-prerequisites)
2. [AWS S3 Remote Backend Setup](#2-aws-s3-remote-backend-setup)
3. [Infrastructure Provisioning via Terraform](#3-infrastructure-provisioning-via-terraform)
4. [GitHub Repository Secrets Configuration](#4-github-repository-secrets-configuration)
5. [Configuring GitHub Actions Self-Hosted Runner on Lightsail](#5-configuring-github-actions-self-hosted-runner-on-lightsail)
6. [Domain, Host NGINX & SSL (Certbot) Configuration](#6-domain-host-nginx--ssl-certbot-configuration)
7. [Triggering CI/CD & Deploying](#7-triggering-cicd--deploying)
8. [Testing Zero-Downtime Blue-Green Deployment & Rollback](#8-testing-zero-downtime-blue-green-deployment--rollback)
9. [Troubleshooting & Verification](#9-troubleshooting--verification)

---

## 1. Prerequisites

Before you begin, ensure you have the following installed and configured:

| Tool | Recommended Version | Purpose |
| :--- | :--- | :--- |
| **Git** | `2.x+` | Version control |
| **AWS CLI** | `v2.x` | Authenticating and managing AWS resources |
| **Terraform** | `1.5.0+` | Infrastructure as Code |
| **Node.js & npm** | Node `24+`, npm `10+` | Local frontend development & testing |
| **GitHub Account** | Free / Pro | Repository hosting & GitHub Actions |
| **Custom Domain** | Any DNS provider (Cloudflare, Route53, Namecheap, etc.) | SSL & subdomain routing |

### Clone the Repository
Clone your repository (or fork) to your local machine:
```bash
git clone https://github.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>.git
cd <YOUR_REPO_NAME>
```

---

## 2. AWS S3 Remote Backend Setup

Terraform stores its state in an encrypted S3 bucket to allow collaboration and prevent state corruption.

### 2.1 Create S3 State Bucket
Choose a **globally unique** bucket name (e.g., `my-todo-infra-tfstate-<unique-suffix>`):

```bash
# Set your preferred AWS Region and globally unique bucket name
export AWS_REGION="<YOUR_AWS_REGION>" # e.g. ap-south-1 or us-east-1
export BUCKET_NAME="<YOUR_UNIQUE_S3_BUCKET_NAME>"

# Create the S3 bucket
# (Note: Omit --create-bucket-configuration if using us-east-1)
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"

# Enable Server-Side Encryption (AES256)
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block Public Access
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }'
```

### 2.2 Configure Terraform Backend
Update the backend configuration in `todo-app/terraform/environments/prod/main.tf` with your bucket name and region:
```hcl
terraform {
  backend "s3" {
    bucket  = "<YOUR_UNIQUE_S3_BUCKET_NAME>"
    key     = "prod/terraform.tfstate"
    region  = "<YOUR_AWS_REGION>"
    encrypt = true
  }
}
```

---

## 3. Infrastructure Provisioning via Terraform

Terraform provisions:
- **AWS ECR**: Docker registry with 3-day image retention policy.
- **AWS IAM OIDC Provider & Role**: Keyless GitHub Actions deployment credentials.
- **AWS Lightsail Instance**: Ubuntu VM with 2GB Swap, Docker pre-installed, Static IP, and open firewall ports (22, 80, 443).

### 3.1 Update Variables
Edit `todo-app/terraform/environments/prod/terraform.tfvars`:
```hcl
github_repository = "<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>"
aws_region        = "<YOUR_AWS_REGION>" # e.g. ap-south-1
```

### 3.2 Initialize & Apply Terraform
```bash
cd todo-app/terraform/environments/prod

# Initialize Terraform plugins and S3 backend
terraform init

# Review the infrastructure plan
terraform plan

# Apply the infrastructure
terraform apply -auto-approve
```

### 3.3 Save Terraform Outputs
Upon completion, Terraform will output values like:
```text
ecr_repository_url    = "<YOUR_AWS_ACCOUNT_ID>.dkr.ecr.<YOUR_AWS_REGION>.amazonaws.com/todo-app"
github_role_arn       = "arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/github-actions-deploy-role"
lightsail_public_ip   = "<LIGHTSAIL_PUBLIC_IP>"
```
Keep these values handy for the next steps.

---

## 4. GitHub Repository Secrets Configuration

Navigate to your GitHub repository:
**Settings $\rightarrow$ Secrets and variables $\rightarrow$ Actions $\rightarrow$ New repository secret**

Add the following two secrets:

| Secret Name | Value | Description |
| :--- | :--- | :--- |
| `AWS_OIDC_ROLE_ARN` | `arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/github-actions-deploy-role` | Value from Terraform output `github_role_arn` |
| `AWS_REGION` | `<YOUR_AWS_REGION>` | Your AWS region (e.g. `ap-south-1`) |

> [!NOTE]
> Because we use OpenID Connect (OIDC), you **never** need to store permanent `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` secrets in GitHub!

---

## 5. Configuring GitHub Actions Self-Hosted Runner on Lightsail

The CD pipeline runs directly on your Lightsail VM to deploy containers seamlessly.

### 5.1 SSH into your Lightsail Instance
```bash
# Retrieve the private key generated by Terraform (if needed)
cd todo-app/terraform/environments/prod
terraform output -raw lightsail_private_key > lightsail_key.pem
chmod 400 lightsail_key.pem

# SSH into the server
ssh -i lightsail_key.pem ubuntu@<LIGHTSAIL_PUBLIC_IP>
```

### 5.2 Install the GitHub Actions Runner
1. In GitHub, go to: **Settings $\rightarrow$ Actions $\rightarrow$ Runners $\rightarrow$ New self-hosted runner**.
2. Select **Linux** and architecture **x64** (or **ARM64** depending on your instance bundle).
3. Run the commands on your Lightsail instance:

```bash
# Create runner directory
mkdir -p ~/actions-runner && cd ~/actions-runner

# Download runner package (check GitHub for latest version)
curl -o actions-runner-linux-x64-2.322.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.322.0/actions-runner-linux-x64-2.322.0.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-2.322.0.tar.gz

# Configure runner (replace with your repository and fresh registration token)
./config.sh --url https://github.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME> --token <YOUR_REGISTRATION_TOKEN> --unattended

# Install and start runner as a background system service
sudo ./svc.sh install
sudo ./svc.sh start
```

---

## 6. Domain, Host NGINX & SSL (Certbot) Configuration

Host NGINX listens on ports 80 and 443, handles SSL certificates via Certbot, and forwards traffic to the internal Docker Blue-Green proxy running on `127.0.0.1:3000`.

### 6.1 Configure DNS A-Record
In your DNS provider (Cloudflare / Route 53 / Namecheap / GoDaddy):
- **Type**: `A`
- **Name / Host**: `<YOUR_SUBDOMAIN>` (e.g. `todo` or `@` for root domain)
- **Value / IPv4**: `<LIGHTSAIL_PUBLIC_IP>`
- **TTL**: Auto / 5 mins

### 6.2 Install NGINX & Certbot on the Host
On your Lightsail instance:
```bash
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx
```

### 6.3 Create Host NGINX Configuration
Create `/etc/nginx/sites-available/todo-app`:
```bash
sudo nano /etc/nginx/sites-available/todo-app
```
Paste the following (replace `<YOUR_DOMAIN>` with your actual domain, e.g., `todo.yourdomain.com`):
```nginx
server {
    listen 80;
    listen [::]:80;
    
    server_name <YOUR_DOMAIN>;

    access_log /var/log/nginx/todo-app.access.log;
    error_log /var/log/nginx/todo-app.error.log;

    location / {
        proxy_pass http://127.0.0.1:3000;
        
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### 6.4 Enable Site and Obtain SSL Certificate
```bash
# Enable the site
sudo ln -sf /etc/nginx/sites-available/todo-app /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test NGINX syntax and reload
sudo nginx -t
sudo systemctl reload nginx

# Generate SSL certificate using Let's Encrypt (Certbot)
sudo certbot --nginx -d <YOUR_DOMAIN>
```
Follow the interactive prompt to complete SSL generation. Certbot will automatically add HTTPS (port 443) and auto-redirect port 80 to 443.

---

## 7. Triggering CI/CD & Deploying

### 7.1 Push Code to GitHub
```bash
git add .
git commit -m "feat: complete devops pipeline setup"
git push origin main
```

### 7.2 What Happens Automatically:
1. **GitHub Actions CI ([`ci.yaml`](file:///Users/rohansingh/Desktop/projects/dev-ops%20project/.github/workflows/ci.yaml))**:
   - Runs `npm ci`, `oxlint`, and `prettier --check`.
   - Runs **OWASP Dependency Check** for vulnerability scanning.
   - Builds Docker image and scans with **Aquasec Trivy**.
   - Authenticates via AWS OIDC and pushes tags `todo-app:<sha>` and `todo-app:latest` to AWS ECR.
2. **GitHub Actions CD ([`cd.yaml`](file:///Users/rohansingh/Desktop/projects/dev-ops%20project/.github/workflows/cd.yaml))**:
   - Triggers on the self-hosted Lightsail runner.
   - Authenticates with ECR via OIDC.
   - Executes [`deploy-blue-green.sh`](file:///Users/rohansingh/Desktop/projects/dev-ops%20project/todo-app/scripts/deploy-blue-green.sh).
   - Starts the candidate container on the alternate slot, verifies `/health`, and switches traffic with **zero downtime**.

---

## 8. Testing Zero-Downtime Blue-Green Deployment & Rollback

### 8.1 Happy Path (Successful Zero-Downtime Deployment)
1. Make a visible change in `src/App.tsx`.
2. Commit and push to `main`.
3. Watch the GitHub Actions logs.
4. While the deployment is running, send continuous requests:
   ```bash
   while true; do curl -s -o /dev/null -w "%{http_code}\n" https://<YOUR_DOMAIN>; sleep 0.5; done
   ```
   **Result:** All requests return `200 OK` continuously with **0 failed requests** during traffic migration.

### 8.2 Failure Path (Automated Rollback Test)
1. Intentionally break the health check in `nginx.conf` (e.g. set status 500).
2. Commit and push.
3. Observe CD pipeline behavior:
   - Starts new container on idle slot.
   - Polls `/health` endpoint and detects failure.
   - Initiates **Automatic Rollback**: Terminates the unhealthy container candidate.
   - Active container remains completely untouched and live on `https://<YOUR_DOMAIN>`.
   - CD workflow exits with error code `1` and alerts the team.

---

## 9. Troubleshooting & Verification

| Symptom | Cause | Resolution |
| :--- | :--- | :--- |
| **`ERR_TIMED_OUT` on HTTPS** | Port 443 blocked in Lightsail firewall | In AWS Lightsail Console $\rightarrow$ Networking $\rightarrow$ Add **HTTPS (Port 443)** to IPv4 firewall. |
| **`404 Not Found` when accessing IP** | Host NGINX only responds to custom domain | Access via `https://<YOUR_DOMAIN>` or check `server_name` in `/etc/nginx/sites-available/todo-app`. |
| **`failed to bind host port: address already in use`** | Process conflict on port 80/3000 | Run `sudo ss -tulpn \| grep -E ':80\|:3000'` to identify conflicting PID and terminate it. |
| **ECR Image Pull Permission Denied** | OIDC Role ARN mismatch | Verify `AWS_OIDC_ROLE_ARN` secret in GitHub matches Terraform output `github_role_arn`. |
| **Health Check Timeout** | Application took longer than 30s to boot | Increase `HEALTHCHECK_MAX_RETRIES` in `deploy-blue-green.sh` if running on small instance bundles. |

### Useful Server Inspection Commands
```bash
# Check running containers
docker ps

# View live container logs
docker logs -f todo-proxy
docker logs -f todo-app-green

# Test internal health endpoint locally
curl -i http://127.0.0.1:3000/health

# Check host NGINX status
sudo systemctl status nginx
sudo journalctl -u nginx -n 50 --no-pager
```
