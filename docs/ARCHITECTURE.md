# System Architecture & Infrastructure Overview

This document provides a comprehensive breakdown of the cloud infrastructure, CI/CD pipelines, containerization, and networking architecture for the Todo DevOps application.

---

## 1. High-Level Architecture Diagram

```mermaid
flowchart TB
    subgraph Users ["External Traffic"]
        Browser["User Browser"]
    end

    subgraph DNSProvider ["DNS Layer"]
        DNS["DNS A-Record: todo.utilsfirst.com"]
    end

    subgraph AWS ["AWS Cloud Infrastructure"]
        subgraph IAM ["Security & IAM"]
            OIDC["GitHub Actions OIDC Identity Provider"]
            Role["github-actions-deploy-role"]
            OIDC --> Role
        end

        subgraph Storage ["Artifact Registry & State"]
            S3["AWS S3 Remote State Bucket (Encrypted)"]
            ECR["AWS ECR (Todo App Images + 3-Day Lifecycle)"]
        end

        subgraph Lightsail ["AWS Lightsail Instance (Ubuntu 22.04)"]
            Firewall["Lightsail Firewall (Ports: 22, 80, 443)"]
            
            subgraph HostOS ["Host OS Layer"]
                HostNginx["Host NGINX (SSL Termination + Port 80/443)"]
                Certbot["Let's Encrypt SSL (Auto-Renewal)"]
                Runner["GitHub Actions Self-Hosted Runner"]
                Certbot -.-> HostNginx
            end

            subgraph DockerNet ["Docker Bridge: todo-network"]
                Proxy["todo-proxy (Nginx Gateway on 127.0.0.1:3000)"]
                
                subgraph Slots ["Blue / Green Application Slots"]
                    Blue["todo-app-blue:8080 (Slot A)"]
                    Green["todo-app-green:8080 (Slot B)"]
                end
                
                Proxy -.->|"Active Traffic"| Blue
                Proxy -.->|"Active Traffic"| Green
            end

            HostNginx -->|"proxy_pass 127.0.0.1:3000"| Proxy
        end
    end

    subgraph GitHub ["GitHub Platform"]
        Repo["GitHub Repository (main branch)"]
        CI["GitHub Actions: CI (Test, Scan, Build, Push)"]
        CD["GitHub Actions: CD (Self-Hosted Runner Deploy)"]
        
        Repo --> CI
        CI --> CD
    end

    Browser --> DNS
    DNS --> Firewall
    Firewall --> HostNginx
    CI -->|"OIDC Auth & Push Image"| ECR
    CD -->|"OIDC Auth & Pull Image"| ECR
    Runner -->|"Executes deploy-blue-green.sh"| DockerNet
```

---

## 2. Component Breakdown

### 2.1 Frontend Application Layer
- **Framework**: React 19 + TypeScript + Vite + Tailwind CSS.
- **Serving Engine**: Multi-stage Docker build utilizing unprivileged `nginxinc/nginx-unprivileged:alpine-slim`.
- **Health Check Endpoint**: Dedicated `/health` endpoint returning `{"status":"healthy"}` (HTTP 200 OK) with logging disabled to avoid polluting access logs.
- **SPA Routing**: Configured with `try_files $uri $uri/ /index.html;` to support client-side routing.

---

### 2.2 Terraform Infrastructure as Code (IaC)
- **S3 Remote Backend**: Centralized remote state with AES-256 encryption (`prod/terraform.tfstate`).
- **ECR Module**:
  - Secure container registry with vulnerability scanning on push.
  - **Lifecycle Policy**: Protects the `latest` tag permanently and automatically expires older image versions/SHAs after **3 days** to optimize storage costs.
- **OIDC Module**:
  - OpenID Connect federation allowing GitHub Actions to authenticate directly with AWS without long-lived access keys (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`).
  - Scoped strictly to repository `RohanSinghProgrammer/todo-devops`.
- **Lightsail Module**:
  - Ubuntu instance provisioned with 2GB swap space and automated Docker installation via `user_data`.
  - Static IP attachment for stable domain mapping.
  - Firewall configuration allowing TCP ports `22` (SSH), `80` (HTTP), and `443` (HTTPS).

---

### 2.3 CI/CD Automation Pipeline

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Developer
    participant GH as GitHub (main)
    participant CI as CI Runner (ubuntu-latest)
    participant ECR as AWS ECR
    participant CD as CD Runner (Lightsail Self-Hosted)
    participant Server as Lightsail Docker Host

    Dev->>GH: Push / Merge Pull Request
    GH->>CI: Trigger "CI - Build and Push"
    CI->>CI: Lint (oxlint) & Format Check (prettier)
    CI->>CI: Security: OWASP Dependency Check
    CI->>CI: Build Local Docker Image
    CI->>CI: Security: Trivy Vulnerability Scan
    CI->>ECR: Assume OIDC Role & Push Image (SHA + latest)
    
    GH->>CD: Trigger "CD - Deploy to Lightsail"
    CD->>ECR: Assume OIDC Role & Pull Image (SHA)
    CD->>Server: Run deploy-blue-green.sh
    Server->>Server: Start candidate on idle slot (e.g. green)
    Server->>Server: Poll http://127.0.0.1:8080/health
    alt Health Check Passes
        Server->>Server: Reload todo-proxy (nginx -s reload)
        Server->>Server: Decommission old slot (blue)
        Server-->>CD: Exit 0 (Deployment Successful)
    else Health Check Fails
        Server->>Server: Terminate candidate (green)
        Server->>Server: Keep active slot (blue) untouched
        Server-->>CD: Exit 1 (Automatic Rollback)
    end
```

---

## 3. Zero-Downtime Blue-Green Deployment Model

```mermaid
stateDiagram-v2
    [*] --> Idle: Blue is Active on 127.0.0.1:3000
    
    state "Deploy Step 1" as S1
    state "Deploy Step 2" as S2
    state "Deploy Step 3 (Success)" as S3
    state "Deploy Step 3 (Failure)" as S4

    Idle --> S1: Pull new SHA image
    S1 --> S2: Start Green on internal port
    S2 --> S3: /health returns 200 OK
    S2 --> S4: /health returns Error / Timeout
    
    S3 --> Idle: Proxy reloads to Green & Blue stops (0 Downtime)
    S4 --> Idle: Green killed & Blue remains active (Instant Rollback)
```

1. **Host NGINX (SSL Termination)**: Always listens on ports 80/443 and proxies to `http://127.0.0.1:3000`.
2. **`todo-proxy` (Internal Gateway)**: Binds to `127.0.0.1:3000` on the `todo-network` Docker bridge.
3. **Application Slots**:
   - **Slot Blue**: `todo-app-blue:8080`
   - **Slot Green**: `todo-app-green:8080`
4. **Traffic Switch**: When the idle slot passes health checks, `todo-proxy` reloads its upstream configuration via `nginx -s reload`, seamlessly transferring active traffic with **zero dropped connections**.
