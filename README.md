# Drupal on AWS — Production DevOps Project

A production-grade Drupal 11 application running on AWS, built entirely with code across six phases.
This project was built as part of the Bincom Academy DevOps/InfraCloud class.

**GitHub:** [RealKingHubs/drupal-app-to-aws-production](https://github.com/RealKingHubs/drupal-app-to-aws-production)

---

## What This Project Does

This is a real multi-server Drupal application deployed on AWS. Everything in this repository — the infrastructure, the server configuration, the container image, the CI/CD pipeline, and the monitoring — was built from scratch and works end to end.

When you run this project, you get:

- Two EC2 servers running Drupal 11 behind a load balancer
- A managed MySQL database with a read replica in a second availability zone
- Automatic scaling when traffic increases
- A pipeline that builds, tests, and deploys on every push to GitHub
- Prometheus and Grafana showing live metrics from every layer
- ELK stack collecting Nginx and Drupal logs from both servers

---

## Architecture

```
Internet
    │
    ▼
Application Load Balancer  (public subnets, us-east-1a and us-east-1b)
    │                │
    ▼                ▼
EC2 Server 1     EC2 Server 2      (private subnets)
us-east-1a       us-east-1b
    │                │
    └────────┬───────┘
             ▼
RDS MySQL Primary (us-east-1a) ──► RDS Read Replica (us-east-1b)
             │
             ▼
      S3 Bucket (file uploads)
```

Traffic enters through the ALB. The EC2 servers are in private subnets — there is no way to reach them directly from the internet. The database is in isolated database subnets that only the application servers can reach.

---

## Project Structure

```
drupal-aws-infra/
├── terraform/
│   ├── environments/production/    # Root module: calls all other modules
│   └── modules/
│       ├── vpc/                    # VPC, subnets, IGW, NAT Gateways, route tables
│       ├── security-groups/        # ALB, app, and database security groups
│       ├── alb/                    # Application Load Balancer and target group
│       ├── asg/                    # Launch template and Auto Scaling Group
│       ├── rds/                    # MySQL primary and read replica
│       ├── s3/                     # S3 bucket with versioning
│       └── billing-alarm/          # CloudWatch billing alarms
├── ansible/
│   ├── site.yml                    # Main playbook — runs all roles
│   ├── monitoring.yml              # Prometheus, Grafana, exporters
│   ├── cloudwatch-exporter.yml     # RDS and ALB metrics from CloudWatch
│   ├── filebeat.yml                # Log shipping from EC2 to ELK
│   ├── inventory/aws_ec2.yml       # Dynamic inventory via amazon.aws.aws_ec2
│   ├── group_vars/all.yml          # Variables (fill in your values here)
│   └── roles/
│       ├── common/                 # System packages, timezone, dpkg lock wait
│       ├── php/                    # PHP 8.3-FPM via Ondrej Sury PPA
│       ├── nginx/                  # Nginx, Drupal vhost, /health endpoint
│       ├── drupal/                 # Composer, Drupal 11, Drush 13, site install
│       └── filesync/               # rsync cron between servers every 5 minutes
├── docker/
│   ├── Dockerfile                  # Custom Drupal image from php:8.3-fpm-bookworm
│   ├── nginx/drupal.conf           # Nginx config for Docker
│   └── php/php.ini                 # PHP settings for Drupal
├── docker-compose.yml              # Local dev: mysql + drupal-fpm + nginx
├── kubernetes/
│   ├── kind-cluster.yml            # Kind cluster with ingress port mappings
│   ├── namespace.yml
│   ├── configmap.yml
│   ├── secret.yml
│   ├── mysql-pvc.yml
│   ├── mysql-deployment.yml
│   ├── mysql-service.yml
│   ├── drupal-pvc.yml
│   ├── drupal-deployment.yml
│   ├── drupal-service.yml
│   ├── nginx-configmap.yml
│   ├── nginx-deployment.yml
│   ├── nginx-service.yml
│   ├── hpa.yml
│   └── ingress.yml
├── .github/workflows/
│   └── drupal-pipeline.yml         # Five-job GitHub Actions pipeline
├── scripts/
│   ├── setup-github-oidc.sh        # Creates IAM role for GitHub Actions (OIDC)
│   ├── cleanup-github-oidc.sh      # Removes the IAM role
│   └── start-monitoring.sh         # Opens SSM tunnels for Grafana and Prometheus
├── logging/
│   ├── docker-compose.logging.yml  # ELK stack: Elasticsearch, Logstash, Kibana
│   └── logstash/pipeline.conf      # Log parsing pipeline
├── monitoring/
│   ├── prometheus/prometheus.yml   # Prometheus scrape config
│   └── prometheus/alerts.yml       # Alert rules
└── docs/
    ├── screenshots/
    ├── 01-architecture.md
    ├── 02-troubleshooting-log.md
    └── 03-phase2-setup.md
```

---

## Prerequisites

Before running anything, make sure you have these installed:

| Tool | Version used | How to install |
|---|---|---|
| Terraform | 1.7+ | [developer.hashicorp.com/terraform](https://developer.hashicorp.com/terraform/install) |
| Ansible | 9+ | `sudo pip3 install ansible boto3 botocore --break-system-packages` |
| AWS CLI | 2.x | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| Docker Desktop | Latest | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) |
| Kind | 0.29+ | `curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind` |
| kubectl | 1.34+ | Comes with Docker Desktop |
| Session Manager plugin | Latest | [docs.aws.amazon.com/systems-manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) |

You also need an AWS account with sufficient IAM permissions to create VPCs, EC2 instances, RDS, ALB, S3, IAM roles, and CloudWatch resources.

---

## Phase 1 — Infrastructure with Terraform

### What it builds

- VPC with CIDR `10.0.0.0/16` across two availability zones
- Public subnets `10.0.1.0/24` and `10.0.2.0/24` — for the ALB and NAT Gateways
- Private subnets `10.0.11.0/24` and `10.0.12.0/24` — for the EC2 servers
- Database subnets `10.0.21.0/24` and `10.0.22.0/24` — isolated, for RDS only
- Two NAT Gateways, one per AZ, so private servers can reach the internet
- Application Load Balancer with health checks on `/health`
- Auto Scaling Group with min 2, desired 2, max 4 EC2 t2.micro instances
- RDS MySQL 8.0 primary in us-east-1a and read replica in us-east-1b
- S3 bucket with versioning, encryption, and lifecycle rules
- CloudWatch billing alarms at 50% and 90% of a $50 monthly budget

### How to run it

**1. Set up your Terraform backend first**

```bash
# Create the S3 bucket for state (replace ACCOUNT_ID with your AWS account ID)
aws s3 mb s3://drupal-aws-tfstate-ACCOUNT_ID --region us-east-1

# Create the DynamoDB table for state locking
aws dynamodb create-table \
  --table-name drupal-aws-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

**2. Create your variables file**

```bash
cd terraform/environments/production
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and fill in:

```hcl
project          = "drupal-aws"
environment      = "production"
aws_region       = "us-east-1"
db_password      = "your-secure-password-here"  # no / @ or " characters
admin_ip_cidr    = "YOUR.IP.ADDRESS/32"          # your laptop IP for monitoring access
alert_email      = "your@email.com"
```

Get your current IP with `curl https://checkip.amazonaws.com`.

**3. Apply**

```bash
terraform init
terraform plan -out=tfplan.out
terraform apply tfplan.out
```

**4. Save the outputs**

```bash
terraform output
```

You will need the ALB DNS name, RDS endpoint, S3 bucket name, and VPC ID for the next phases.

### Key design decisions

**Three network tiers with no shortcuts.** The ALB is the only resource in public subnets. EC2 servers are in private subnets. RDS is in database subnets that only the app security group can reach on port 3306.

**Two NAT Gateways, not one.** One NAT Gateway per AZ means that if us-east-1a has a problem, instances in us-east-1b still have outbound internet access through their own gateway.

**ELB health checks, not EC2 health checks.** The ASG uses ELB health check type so it terminates unhealthy instances based on whether Drupal is actually responding, not just whether the EC2 instance is running.

---

## Phase 2 — Application Configuration with Ansible

### How it works

Ansible connects to EC2 instances through AWS Systems Manager Session Manager. There are no SSH keys. Port 22 is not open to the internet. The SSM agent is pre-installed on all instances via Terraform userdata.

The dynamic inventory discovers instances at runtime using the `amazon.aws.aws_ec2` plugin. You do not need to hard-code any IP addresses.

### Before you run

Fill in `ansible/group_vars/all.yml` with your real values from Phase 1:

```yaml
drupal_db_host: "your-rds-endpoint-without-port"
drupal_db_password: "your-db-password"
drupal_s3_bucket: "drupal-aws-production-files-xxxx"
drupal_admin_password: "your-admin-password"
```

### Install Ansible collections

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

### Run the main playbook

```bash
ansible-playbook -i inventory/aws_ec2.yml site.yml
```

The playbook runs five roles in order on both servers simultaneously:

| Role | What it does |
|---|---|
| common | Waits for dpkg lock, updates packages, sets UTC timezone |
| php | Adds Ondrej Sury PPA, installs PHP 8.3-FPM and all Drupal extensions |
| nginx | Installs Nginx, deploys Drupal vhost config with `/health` endpoint |
| drupal | Installs Composer and Drupal 11, runs Drush site:install |
| filesync | Exchanges SSH keys between servers, sets up rsync cron every 5 minutes |

After all roles complete, both servers get an unconditional Nginx and PHP-FPM restart. Then the playbook verifies `/health` returns 200 on each server before reporting success.

### Two design decisions worth knowing

**Only one server runs the Drupal install.** Both servers share the same RDS database. If both ran `drush site:install` simultaneously, they would crash each other. The playbook restricts the install to the alphabetically first instance ID in the inventory — chosen by sorting, not by AWS API response order, so it is the same instance every time you run.

**Nginx always restarts at the end, never just reloads.** The nginx role configures the document root pointing to `/var/www/html/drupal/web`, but that directory does not exist until the drupal role runs. If Ansible only reloads Nginx at the point the config changes, worker processes start with a stale state. A full restart after everything is in place guarantees clean workers every run.

### Verify it worked

```bash
# Check both targets are healthy behind the ALB
aws elbv2 describe-target-health \
  --target-group-arn $(cd terraform/environments/production && terraform output -raw target_group_arn)
```

Both instances should show `"State": "healthy"`.

---

## Phase 3 — Docker and Kubernetes

### Building the Docker image

The image is built from `php:8.3-fpm-bookworm` — not the official Drupal image. This means every layer is visible and every dependency is explicit.

```bash
docker build -t drupal-custom:latest ./docker/
```

The build installs PHP extensions, copies Composer from the official Composer image, then runs `composer create-project` to pull Drupal 11 and Drush 13. The timeout is set to 600 seconds because Drupal core is a large download.

### Running locally with Docker Compose

```bash
docker compose up -d

# Wait about 60 seconds for MySQL to initialize, then install Drupal
docker compose exec drupal-fpm vendor/bin/drush site:install standard \
  --db-url=mysql://drupal_admin:drupal_password@mysql:3306/drupal_db \
  --site-name="Drupal AWS Portfolio Project" \
  --account-name=admin \
  --account-pass=admin123 \
  --account-mail=admin@example.com \
  --yes
```

Open `http://localhost:8080` in your browser.

The three services mirror the production AWS architecture:

- `mysql` — MySQL 8.0, same engine as production RDS
- `drupal-fpm` — PHP-FPM running the Drupal application
- `nginx` — Reverse proxy, proxies PHP requests to drupal-fpm on port 9000

**Important:** `settings.php` is not mounted from the host. Drush writes it inside the container during the install step. This is the correct security pattern — no credential files on the host filesystem.

To stop and remove everything including volumes:

```bash
docker compose down -v
```

### Deploying to Kubernetes with Kind

**Create the cluster**

```bash
kind create cluster --config kubernetes/kind-cluster.yml
```

This creates one control-plane node and two workers. The control-plane is labeled `ingress-ready=true` so the Nginx ingress controller can schedule on it.

**Load images into Kind**

Kind cannot see your local Docker images directly. You need to load them manually using `docker save` and `ctr import` because `kind load docker-image` fails on WSL2 with Docker Desktop due to multi-platform manifest issues:

```bash
docker save drupal-custom:latest -o /tmp/drupal.tar
docker save mysql:8.0 -o /tmp/mysql.tar
docker save nginx:1.25-alpine -o /tmp/nginx.tar

for node in drupal-cluster-control-plane drupal-cluster-worker drupal-cluster-worker2; do
  docker exec -i $node ctr --namespace=k8s.io images import - < /tmp/drupal.tar
  docker exec -i $node ctr --namespace=k8s.io images import - < /tmp/mysql.tar
  docker exec -i $node ctr --namespace=k8s.io images import - < /tmp/nginx.tar
done
```

**Install the Nginx ingress controller**

Pin the version to v1.12.2. The main branch manifest causes a PID file crash on restart with Kubernetes 1.33:

```bash
# Pull and load the ingress controller images first
docker pull --platform linux/amd64 registry.k8s.io/ingress-nginx/controller:v1.12.2
docker pull --platform linux/amd64 registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.4

docker save registry.k8s.io/ingress-nginx/controller:v1.12.2 -o /tmp/ingress.tar
docker save registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.4 -o /tmp/certgen.tar

for node in drupal-cluster-control-plane drupal-cluster-worker drupal-cluster-worker2; do
  docker exec -i $node ctr --namespace=k8s.io images import - < /tmp/ingress.tar
  docker exec -i $node ctr --namespace=k8s.io images import - < /tmp/certgen.tar
done

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.2/deploy/static/provider/kind/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

**Deploy the application**

```bash
kubectl apply -f kubernetes/namespace.yml
kubectl apply -f kubernetes/configmap.yml
kubectl apply -f kubernetes/secret.yml
kubectl apply -f kubernetes/mysql-pvc.yml
kubectl apply -f kubernetes/mysql-deployment.yml
kubectl apply -f kubernetes/mysql-service.yml
kubectl apply -f kubernetes/drupal-pvc.yml
kubectl apply -f kubernetes/drupal-deployment.yml
kubectl apply -f kubernetes/drupal-service.yml
kubectl apply -f kubernetes/nginx-configmap.yml
kubectl apply -f kubernetes/nginx-deployment.yml
kubectl apply -f kubernetes/nginx-service.yml
kubectl apply -f kubernetes/ingress.yml
```

Wait for MySQL to be ready, then install Drupal:

```bash
kubectl get pods -n drupal -w
# Wait until mysql pod shows 1/1 Running, then Ctrl+C

kubectl exec -n drupal deployment/drupal -- vendor/bin/drush site:install standard \
  --db-url=mysql://drupal_admin:drupal_password@mysql-service:3306/drupal_db \
  --site-name="Drupal AWS Portfolio Project" \
  --account-name=admin \
  --account-pass=admin123 \
  --account-mail=admin@example.com \
  --yes
```

Add the hostname to `/etc/hosts`:

```bash
echo "127.0.0.1 k8s.local" | sudo tee -a /etc/hosts
```

Open `http://k8s.local:8090` in your browser.

**What the Kubernetes setup includes**

| Manifest | What it does |
|---|---|
| namespace.yml | Creates the `drupal` namespace |
| configmap.yml | DB host, port, name, username |
| secret.yml | DB password and MySQL root password (base64 encoded) |
| mysql-pvc.yml | 5 GB PersistentVolumeClaim for MySQL data |
| mysql-deployment.yml | MySQL 8.0 with readiness and liveness probes |
| mysql-service.yml | Headless service for direct pod DNS |
| drupal-pvc.yml | 2 GB PVC for Drupal uploaded files |
| drupal-deployment.yml | 2 replicas, init container waits for MySQL |
| drupal-service.yml | ClusterIP service on port 9000 |
| nginx-configmap.yml | Nginx config that proxies PHP to drupal-service |
| nginx-deployment.yml | 2 replicas, NodePort 30080 |
| nginx-service.yml | NodePort service |
| hpa.yml | HPA for both drupal and nginx: scale 2-6 pods at 70% CPU |
| ingress.yml | Routes external traffic to nginx-service |

**Delete the cluster when done**

```bash
kind delete cluster --name drupal-cluster
```

---

## Phase 4 — CI/CD Pipeline with GitHub Actions

### How authentication works

The pipeline uses OpenID Connect (OIDC) federation. GitHub gets a short-lived token at the start of each job, uses it to assume an IAM role in your AWS account, and the token expires when the job ends. No long-lived access keys are stored anywhere.

**One-time setup**

```bash
bash scripts/setup-github-oidc.sh
```

This creates the OIDC provider and an IAM role named `github-actions-drupal-role` with a least-privilege inline policy scoped to exactly what the pipeline needs.

Add the role ARN as a GitHub secret:

Go to your repo → Settings → Secrets and variables → Actions → New repository secret

| Secret name | Value |
|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/github-actions-drupal-role` |
| `ALB_DNS_NAME` | Your ALB DNS name from `terraform output alb_dns_name` |

**Set up GitHub Environments**

Go to your repo → Settings → Environments:

- Create `staging` — no protection rules
- Create `production` — add yourself as Required reviewer

### The pipeline

The pipeline has five jobs that run in sequence:

```
push to main
      │
      ▼
   1. Build
   Build Docker image, tag with git SHA, push to ECR
      │
      ▼
   2. Test
   PHP syntax check, Drupal files present, integration test
      │
      ▼
   3. Deploy Staging
   Deploy to first EC2 instance via SSM send-command
      │
      ▼
   4. Smoke Test Staging
   Check /health, homepage, and login page against the ALB
      │
      ▼
   ⏸ Manual Approval
   Pipeline pauses. Someone clicks "Review deployments" in GitHub.
      │
      ▼
   5. Deploy Production
   Deploy to all EC2 instances, final health check
```

Jobs 3, 4, and 5 only run on pushes to `main`, not on pull requests.

**To trigger the pipeline**

```bash
git add .
git commit -m "your message"
git push origin main
```

Watch it at: `https://github.com/RealKingHubs/drupal-app-to-aws-production/actions`

**To clean up the OIDC role when the project is done**

```bash
bash scripts/cleanup-github-oidc.sh
```

---

## Phase 5 — Monitoring with Prometheus and Grafana

### What runs on EC2

All monitoring components run on the first EC2 instance. They are accessed from your laptop via SSM port forwarding tunnels.

| Component | Port | What it does |
|---|---|---|
| Prometheus | 9090 | Scrapes all targets every 15 seconds, stores 7 days |
| Grafana | 3000 | Dashboards and alert management |
| Node Exporter | 9100 | CPU, memory, disk, network on both EC2 instances |
| Nginx Exporter | 9113 | Request rate from Nginx stub_status endpoint |
| CloudWatch Exporter | 9106 | RDS and ALB metrics pulled from AWS CloudWatch API |

### Deploy the monitoring stack

```bash
cd ansible
ansible-playbook -i inventory/aws_ec2.yml monitoring.yml
ansible-playbook -i inventory/aws_ec2.yml cloudwatch-exporter.yml
```

### Access Grafana and Prometheus

The monitoring ports are not publicly accessible. Open SSM tunnels from your laptop:

```bash
bash scripts/start-monitoring.sh
```

Or open them manually:

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=drupal-aws-production-app" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text | awk '{print $1}')

# Grafana
aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'

# Prometheus (in a second terminal)
aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["9090"],"localPortNumber":["9090"]}'
```

Then open:
- Grafana: `http://localhost:3000` (admin / admin)
- Prometheus: `http://localhost:9090`

### What the dashboard tracks

| Category | Metrics |
|---|---|
| EC2 servers | CPU %, memory %, disk %, network traffic in/out, system load 1m and 5m |
| Web server | Request rate per second, active Nginx connections |
| Load balancer | ALB request count, response time average and p99, 4xx and 5xx error count |
| Database | RDS active connections, read latency, write latency, CPU, IOPS, free storage |

### Alert rules

| Alert | Condition | Severity |
|---|---|---|
| HighCPUUsage | CPU above 80% for 5 minutes | warning |
| CriticalCPUUsage | CPU above 95% for 2 minutes | critical |
| HighMemoryUsage | Memory above 85% for 5 minutes | warning |
| DiskSpaceLow | Root partition above 80% for 5 minutes | warning |
| HighDiskIO | Disk utilization above 90% for 5 minutes | warning |
| InstanceDown | Target unreachable for 1 minute | critical |
| NginxDown | Nginx exporter unreachable for 1 minute | critical |
| HighNginxConnections | Active connections above 500 for 5 minutes | warning |
| HighRDSConnections | RDS connections above 80 for 5 minutes | warning |
| HighRDSCPU | RDS CPU above 80% for 5 minutes | warning |
| HighRDSReadLatency | Read latency above 50ms for 5 minutes | warning |
| ALBHighErrorRate | More than 10 5xx errors in 5 minutes | critical |
| ALBNoHealthyHosts | Healthy host count below 1 for 1 minute | critical |

### Important: CloudWatch Exporter statistics config

The AWS CloudWatch API only accepts `SampleCount`, `Average`, `Sum`, `Minimum`, and `Maximum` as standard statistics. The p99 percentile is an extended statistic and must be declared under `aws_extended_statistics`, not `aws_statistics`. Using `aws_statistics: [Average, p99]` causes the API to reject the request with a 400 error and the exporter silently drops all other metrics from that namespace.

Correct config in `monitoring/prometheus/cloudwatch.yml`:

```yaml
- aws_namespace: AWS/ApplicationELB
  aws_metric_name: TargetResponseTime
  aws_dimensions: [LoadBalancer]
  aws_statistics: [Average]
  aws_extended_statistics: [p99]
  period_seconds: 60
```

---

## Phase 6 — Centralized Logging with the ELK Stack

### Architecture

The ELK stack runs on your laptop inside Docker. EC2 instances ship logs through an SSM reverse port forwarding tunnel. This means no logging infrastructure runs in AWS and there is no extra cost.

```
EC2 Instances
    │ (Filebeat reads log files)
    │ (sends to 127.0.0.1:5044)
    │
    ▼
SSM Reverse Tunnel
    │ (carries traffic from EC2 back to your laptop)
    │
    ▼
Logstash (port 5044 on your laptop, inside Docker)
    │ (parses and formats logs)
    │
    ▼
Elasticsearch (port 9200, inside Docker)
    │ (stores log documents)
    │
    ▼
Kibana (port 5601, inside Docker)
    (search and visualize)
```

### Start the ELK stack

```bash
cd logging
docker compose -f docker-compose.logging.yml up -d
docker compose -f docker-compose.logging.yml ps
```

Wait for Elasticsearch to show healthy (about 60 seconds), then open Kibana at `http://localhost:5601`.

**Critical configuration note:** In the Logstash pipeline config, Elasticsearch must be referenced by its Docker service name, not localhost. Inside a Docker container, localhost refers to the container itself:

```
# Wrong
hosts => ["localhost:9200"]

# Correct
hosts => ["elasticsearch:9200"]
```

### Open the SSM log shipping tunnel

Filebeat on the EC2 instances sends logs to its own `127.0.0.1:5044`. You need an SSM reverse tunnel so that traffic reaches your local Logstash:

```bash
aws ssm start-session \
  --target "i-0885a16a4bda259f4" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["localhost"],"portNumber":["5044"],"localPortNumber":["5044"]}'
```

Keep this terminal open while logs need to ship. If port 5044 is already in use on your laptop (Logstash binds to it), use port 5045 as the local port and add `"5045:5044"` to the Logstash ports section in `docker-compose.logging.yml`.

### Deploy Filebeat to EC2

```bash
cd ansible
ansible-playbook -i inventory/aws_ec2.yml filebeat.yml
```

Filebeat ships three log types:

| Log file | Tag | What it contains |
|---|---|---|
| `/var/log/nginx/drupal-access.log` | nginx_access | Every HTTP request: IP, method, response code, bytes |
| `/var/log/nginx/drupal-error.log` | nginx_error | Nginx errors with severity level and full message |
| `/var/log/drupal-bootstrap.log` | drupal | Drupal application events: type, severity, description |

### Create the Kibana Data View

Once logs are flowing, go to Kibana → Management → Stack Management → Kibana → Data Views → Create data view:

- Index pattern: `drupal-logs-*`
- Timestamp field: `@timestamp`

You can verify the index exists first in Dev Tools with `GET _cat/indices?v`.

---

## Security Design

Every security decision in this project was made at design time, not added afterwards.

### No SSH access anywhere

There are no SSH keys in this project. Port 22 is not open to the internet. There is no bastion host. All server access goes through AWS Systems Manager Session Manager, which requires valid AWS credentials and leaves an audit trail in CloudTrail.

### No long-lived AWS keys in GitHub

The CI/CD pipeline uses OIDC federation. GitHub receives a short-lived token when a job starts, uses it to assume a scoped IAM role, and the token expires when the job ends. The only thing stored in GitHub Secrets is the role ARN.

### Least privilege IAM

| Role | Permissions |
|---|---|
| EC2 instance role | SSM access, specific S3 bucket, CloudWatch put metrics, ECR pull from drupal-app repo |
| GitHub Actions role | ECR push to drupal-app, EC2 describe, SSM send-command, ALB describe, S3 get/put on specific bucket |

### Three network tiers

| Tier | What lives there | Who can reach it |
|---|---|---|
| Public | ALB and NAT Gateways | The internet (port 80 only) |
| Private | EC2 application servers | ALB security group on port 80, admin IP on ports 22 and 9100-9113 |
| Database | RDS instances | App security group on port 3306 only |

### Known issue: security group cidr_blocks + self = true conflict

AWS does not allow combining `cidr_blocks` and `self = true` in the same ingress block. If you do this, AWS silently breaks the entire security group rule evaluation. This caused the ALB to stop routing traffic in this project. The fix is to split them into two separate ingress blocks:

```hcl
# Wrong — breaks silently
ingress {
  from_port   = 9100
  to_port     = 9113
  protocol    = "tcp"
  cidr_blocks = [var.admin_ip_cidr]
  self        = true   # cannot combine with cidr_blocks
}

# Correct — two separate blocks
ingress {
  from_port   = 9100
  to_port     = 9113
  protocol    = "tcp"
  cidr_blocks = [var.admin_ip_cidr]
}

ingress {
  from_port = 9100
  to_port   = 9113
  protocol  = "tcp"
  self      = true
}
```

---

## High Availability Design

### What happens when an EC2 server fails

The ALB continuously checks `/health` on each instance every 30 seconds. If an instance fails five consecutive checks, the ALB stops routing traffic to it and the Auto Scaling Group launches a replacement. Users are rerouted within about 60 seconds.

### What happens when an Availability Zone fails

Each AZ has its own EC2 instance, NAT Gateway, and RDS node. The ALB health checks detect the failing AZ and route all traffic to the healthy one. This is why the project uses two NAT Gateways — one in each AZ — rather than one shared gateway.

### What happens when the primary RDS fails

The read replica in us-east-1b promotes itself to the new primary automatically. AWS updates the DNS endpoint. Drupal reconnects when its connection pool retries against the same endpoint address.

### Auto scaling

The ASG has step scaling policies:
- Above 70% average CPU → add instances (up to 4 maximum)
- Below 30% average CPU → remove instances (down to 2 minimum)

---

## Cost Profile

This project ran for 15 days with a total cost of approximately $44.

| Service | Monthly cost | Notes |
|---|---|---|
| 2x NAT Gateways | ~$32 | $0.045/hr each. The biggest cost driver. |
| Application Load Balancer | ~$8 | Minimum hourly charge regardless of traffic |
| RDS Read Replica | ~$4 | The primary is free tier; the replica is not |
| 2x EC2 t2.micro | $0 | Free tier eligible |
| RDS db.t3.micro (primary) | $0 | Free tier eligible |
| S3 bucket | ~$0 | Well under free tier |

**Run `terraform destroy` as soon as you are done to stop all charges.** The NAT Gateways charge by the hour whether they are used or not.

---

## Troubleshooting Log

20 real incidents encountered and resolved during this build. Full details are in `docs/02-troubleshooting-log.md`. A summary:

| # | What broke | Root cause | Fix |
|---|---|---|---|
| 1 | S3 lifecycle rule failing | AWS requires empty `filter {}` even with no filter | Added empty filter block |
| 2 | Terraform template broke Bash | Both use `${VAR}` syntax | Used `$$` in Bash or `file()` instead of `templatefile()` |
| 3 | CIDR validation rejected IP | Trailing space in terraform.tfvars | Trimmed the whitespace |
| 4 | DNS failed mid-apply, errored state | Temporary network failure during terraform apply | `terraform state push` to restore last clean state |
| 5 | Stale DynamoDB state lock | Previous apply was interrupted | `terraform force-unlock LOCK_ID` |
| 6 | db.t2.micro rejected by RDS | MySQL 8.0 free tier needs db.t3.micro | Updated instance class |
| 7 | RDS rejected the password | RDS forbids `/` `@` `"` in passwords | Removed those characters |
| 8 | ASG termination loop | ELB health checks fired before Drupal was installed | Temporary EC2 health checks, switched back after install |
| 9 | Ansible could not connect via SSM | Connection plugin needed single quotes inside double quotes | Fixed ansible.cfg syntax |
| 10 | apt commands failed on first boot | unattended-upgrades held the dpkg lock | Added wait task before any apt commands |
| 11 | Composer scaffold step skipped | Composer skips plugins as root without COMPOSER_ALLOW_SUPERUSER=1 | Added env var and explicit scaffold step |
| 12 | `/health` returned 404 after deployment | Nginx reloaded before Drupal web root existed | Unconditional restart after all roles complete |
| 13 | Second server crashed database install | Both ran `site:install` against the same database | Restricted install to alphabetically first instance |
| 14 | boto3 missing in new terminals | Installed in a virtualenv that needed activation | Reinstalled at system level |
| 15 | GitHub Actions AccessDeniedException | Missing `ssm:ListCommandInvocations` in IAM policy | Added the permission |
| 16 | ECR push failed despite correct policy | `drupal-app*` does not match exact name `drupal-app` | Added both exact ARN and wildcard to resource array |
| 17 | Ansible broke on Prometheus alert rules | Jinja2 tried to interpret `{{ $labels.instance }}` | Wrapped in `{% raw %}` and `{% endraw %}` |
| 18 | CloudWatch Exporter returned only one metric | `p99` in `aws_statistics` causes 400 error, exporter drops everything | Moved `p99` to `aws_extended_statistics` |
| 19 | ALB stopped routing traffic after adding monitoring ports | Combined `cidr_blocks` and `self = true` in one security group rule | Split into two separate ingress blocks |
| 20 | Logstash could not reach Elasticsearch | `localhost` inside a container refers to the container itself | Changed to service name `elasticsearch:9200` |

---

## Common Commands

```bash
# Deploy infrastructure
cd terraform/environments/production
terraform apply

# Configure servers
cd ansible
ansible-playbook -i inventory/aws_ec2.yml site.yml

# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $(cd terraform/environments/production && terraform output -raw target_group_arn)

# Open monitoring access
bash scripts/start-monitoring.sh

# Build and run locally with Docker
docker compose up -d

# Run on Kubernetes
kind create cluster --config kubernetes/kind-cluster.yml
# (load images, install ingress, apply manifests — see Phase 3 above)

# Start ELK logging stack
cd logging && docker compose -f docker-compose.logging.yml up -d

# Destroy all AWS resources when done
cd terraform/environments/production
terraform destroy
```

---

## Environment Variables and Secrets

This project does not store secrets in code. Here is where each credential lives:

| Secret | Where it lives | How it gets there |
|---|---|---|
| DB password | `terraform.tfvars` (not committed) | You set it manually |
| Drupal admin password | `ansible/group_vars/all.yml` (not committed) | You set it manually |
| AWS credentials (local) | `~/.aws/credentials` | `aws configure` |
| AWS credentials (pipeline) | Assumed via OIDC at runtime | `scripts/setup-github-oidc.sh` |
| GitHub Actions role ARN | GitHub Secrets | You add it after running the OIDC script |

Files that must not be committed (already in `.gitignore`):
- `terraform/environments/production/terraform.tfvars`
- `ansible/group_vars/all.yml`
- `*.pem`
- `.terraform/` directories
- `*.tfstate` files

---

## Project Information

| | |
|---|---|
| **Author** | Kingsley |
| **Institution** | Bincom Academy — DevOps/InfraCloud Class |
| **Repository** | github.com/RealKingHubs/drupal-app-to-aws-production |
| **AWS Account** | 09379xxxxxxx |
| **AWS Region** | us-east-1 |
| **Drupal version** | 11.x |
| **PHP version** | 8.3 |
| **Terraform version** | 1.7+ |
| **Ansible version** | 9+ |
| **Kubernetes** | 1.33.1 (Kind) |
