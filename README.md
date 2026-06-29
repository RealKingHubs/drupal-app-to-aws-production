[README.md](https://github.com/user-attachments/files/29452648/README.md)
# Drupal on AWS — Production DevOps Project

A production-grade Drupal 11 deployment on AWS, built with a full DevOps toolchain: Terraform for infrastructure, Ansible for configuration, Docker and Kubernetes for containerization, GitHub Actions for CI/CD, and Prometheus/Grafana plus the ELK stack for observability.

No SSH access is used anywhere in this project. All EC2 access goes through AWS Systems Manager (SSM).

**Repository:** [github.com/RealKingHubs/drupal-app-to-aws-production](https://github.com/RealKingHubs/drupal-app-to-aws-production)

---

## Features

- **Infrastructure as code** — full AWS environment (VPC, ALB, ASG, RDS, S3) provisioned with modular Terraform, remote state in S3 with DynamoDB locking
- **SSH-free server access** — all EC2 configuration via Ansible over AWS SSM, no bastion host, no open port 22
- **Multi-AZ high availability** — resources spread across two availability zones with Auto Scaling and an RDS read replica
- **Containerized everywhere** — custom Docker image for local development, Kind (Kubernetes in Docker) for local cluster testing
- **Keyless CI/CD** — GitHub Actions authenticates to AWS via OIDC federation, no long-lived access keys stored in GitHub
- **Production deployment gate** — manual approval required before deploying to production EC2 instances
- **Full observability stack** — Prometheus, Grafana, Node Exporter, Nginx Exporter, and a CloudWatch Exporter for RDS/ALB metrics, all accessed via SSM tunnels (no public monitoring ports)
- **Centralized logging** — Filebeat ships Nginx and Drupal logs from EC2 to a local ELK stack over an SSM reverse tunnel
- **Defense-in-depth security** — three-tier network segmentation, least-privilege IAM, encrypted storage, no public database access

---

## Architecture Overview

```
Internet
   |
Application Load Balancer (public subnets, 2 AZs)
   |
EC2 Auto Scaling Group (private subnets, 2 AZs)
   |             |
   |             +--> RDS MySQL (database subnets, primary + read replica)
   |
   +--> Node Exporter / Nginx Exporter / CloudWatch Exporter
              |
        Prometheus --> Grafana   (accessed via SSM tunnel)
              |
        Filebeat --> Logstash --> Elasticsearch --> Kibana   (local, via SSM reverse tunnel)
```

| Tier | Subnets | Contains |
|---|---|---|
| Public | `10.0.1.0/24`, `10.0.2.0/24` | ALB, NAT Gateways |
| Private | `10.0.11.0/24`, `10.0.12.0/24` | EC2 application servers |
| Database | `10.0.21.0/24`, `10.0.22.0/24` | RDS MySQL (no public access) |

---

## Prerequisites

| Tool | Version / Notes |
|---|---|
| Terraform | Any recent 1.x release |
| AWS CLI | Configured with credentials that can create VPC, EC2, RDS, S3, IAM resources |
| Ansible | Installed with `boto3` and `botocore` (system-level install recommended, see [Troubleshooting](#troubleshooting)) |
| AWS SSM Session Manager Plugin | Required for SSM-based access and port forwarding tunnels |
| Docker + Docker Compose | For local development stack |
| Kind | For local Kubernetes cluster testing |
| GitHub account with Actions enabled | For CI/CD pipeline |

You do **not** need an SSH key pair. This project does not use SSH for server access.

---

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/RealKingHubs/drupal-app-to-aws-production.git
cd drupal-app-to-aws-production
```

### 2. Provision AWS infrastructure

```bash
cd terraform/environments/production
terraform init
terraform plan -out=tfplan.out
terraform apply tfplan.out
```

This creates the VPC, subnets, ALB, Auto Scaling Group, RDS MySQL instance, S3 bucket, and billing alarms. Note the outputs (ALB DNS name, instance IDs) at the end.

```bash
terraform output
```

### 3. Configure the application servers

Ansible discovers your new EC2 instances automatically via the dynamic inventory plugin. No manual inventory file needed.

```bash
cd ../../../ansible
ansible-playbook site.yml
```

This installs PHP 8.3-FPM, Nginx, Composer, Drupal 11, and Drush, then runs the Drupal site installer on exactly one instance (see [Configuration](#configuration) for why).

### 4. Verify the deployment

```bash
curl http://<alb-dns-name>/health
```

A `200 OK` response confirms the application is healthy.

### 5. Run locally with Docker Compose (optional)

```bash
docker compose up -d
```

Visit `http://localhost:8080`.

### 6. Tear down

```bash
cd terraform/environments/production
terraform destroy
```

Run this as soon as you are done. See [Cost Profile](#cost-profile) below.

---

## Configuration

### Environment Variables

These are used across Terraform, Docker Compose, and the Drupal container.

| Variable | Used By | Description | Example |
|---|---|---|---|
| `DB_HOST` | Drupal container | Database hostname | `mysql` (local) / RDS endpoint (production) |
| `DB_PORT` | Drupal container | Database port | `3306` |
| `DB_NAME` | Drupal container | Drupal database name | `drupal` |
| `DB_USER` | Drupal container | Database username | Set via Kubernetes Secret / RDS master user |
| `DB_PASSWORD` | Drupal container | Database password | Set via Kubernetes Secret. Cannot contain `/`, `@`, or `"` (RDS restriction) |
| `MYSQL_ROOT_PASSWORD` | MySQL container (local only) | Root password for local MySQL container | Base64-encoded in `secret.yml` for Kubernetes |
| `COMPOSER_PROCESS_TIMEOUT` | Docker build | Prevents Composer timeout on slow connections | `600` |
| `COMPOSER_ALLOW_SUPERUSER` | Docker build | Required for Composer plugins (including scaffolding) to run as root | `1` |
| `AWS_ROLE_ARN` | GitHub Actions secret | IAM role assumed via OIDC, only secret needed in CI/CD | `arn:aws:iam::<account-id>:role/github-actions-drupal-role` |

### Terraform Variables

Set these in `terraform/environments/production/terraform.tfvars`. Double-check for trailing whitespace, it breaks CIDR validation (see [Troubleshooting](#troubleshooting)).

| Variable | Description | Example |
|---|---|---|
| `admin_ip_cidr` | Your IP, allowed to reach app servers on port 22/9100-9113 | `203.0.113.5/32` |
| AWS region | Set in provider block | `us-east-1` |

### Why Drupal Installs on Only One Server

Both EC2 instances share the same RDS database. Running `site:install` on both at once causes a database collision. The playbook restricts the install task with:

```yaml
when: inventory_hostname == (groups['all'] | sort | first)
```

This picks the alphabetically first instance ID in the live inventory every run, so it works consistently across re-runs and infrastructure rebuilds.

---

## Repository Structure

```
terraform/
  modules/
    vpc/                VPC, subnets, route tables, IGW, NAT Gateways
    security-groups/    Layered security groups for ALB, app, and database tiers
    alb/                Application Load Balancer and target group
    asg/                Launch template, Auto Scaling Group, scaling policies
    rds/                RDS MySQL primary and read replica
    s3/                 S3 bucket with versioning and encryption
    billing-alarm/      CloudWatch billing alarms via SNS
  environments/production/   Root module that wires up all other modules

ansible/
  inventory/aws_ec2.yml       Dynamic inventory (amazon.aws.aws_ec2 plugin)
  site.yml                    Main playbook, idempotent, runs on all instances
  monitoring.yml               Deploys Prometheus, Grafana, Node Exporter, Nginx Exporter
  cloudwatch-exporter.yml      Deploys CloudWatch Exporter for RDS/ALB metrics
  filebeat.yml                 Deploys Filebeat on all EC2 instances
  roles/
    common/      Base system setup, dpkg lock wait, timezone
    php/          PHP 8.3-FPM and Drupal-required extensions
    nginx/        Nginx, Drupal vhost, /health endpoint
    drupal/       Composer, Drupal 11, Drush 13, site install
    filesync/     rsync between instances via SSH keypair exchange

docker/
  Dockerfile            Custom Drupal 11 image, based on php:8.3-fpm-bookworm
  nginx/drupal.conf     Nginx config, proxies to drupal-fpm:9000
  php/php.ini           PHP settings for Drupal
docker-compose.yml      Local stack: mysql, drupal-fpm, nginx

kubernetes/
  kind-cluster.yml      Kind cluster config with ingress port mappings
  *.yml                 Namespace, ConfigMap, Secret, PVCs, Deployments, Services, HPA, Ingress

.github/workflows/drupal-pipeline.yml   Five-job CI/CD pipeline

scripts/
  setup-github-oidc.sh      Creates OIDC provider and IAM role for GitHub Actions
  cleanup-github-oidc.sh    Removes the IAM role and inline policy
  start-monitoring.sh       Opens SSM tunnels for Grafana and Prometheus

logging/
  docker-compose.logging.yml   ELK stack: Elasticsearch, Logstash, Kibana
  logstash/pipeline.conf       Parses Nginx and Drupal logs into Elasticsearch

monitoring/prometheus/
  prometheus.yml    Scrape config
  alerts.yml        Alert rules for CPU, memory, disk, Nginx, RDS, ALB

docs/   Documentation and troubleshooting log
```

---

## Accessing the Application

| What | How |
|---|---|
| Production site | `http://<alb-dns-name>` |
| Health check | `http://<alb-dns-name>/health` (plain text, returns 200, no PHP/DB dependency) |
| Local Docker Compose | `http://localhost:8080` |
| Local Kubernetes (Kind) | `http://k8s.local:8090` (add to `/etc/hosts` first) |

---

## Server Access (No SSH)

This project does not use SSH. All EC2 access is through AWS SSM Session Manager.

```bash
aws ssm start-session --target <instance-id>
```

File transfers to EC2 go through the S3 bucket rather than SCP.

---

## Monitoring

Prometheus and Grafana run on the first EC2 instance and are reached from your laptop through SSM port forwarding, no public ports are opened.

```bash
# Grafana
aws ssm start-session --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'

# Prometheus
aws ssm start-session --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["9090"],"localPortNumber":["9090"]}'
```

Or use the helper script:

```bash
./scripts/start-monitoring.sh
```

Then visit `http://localhost:3000` (Grafana, default login `admin`/`admin`) and `http://localhost:9090` (Prometheus).

### What's Monitored

| Category | Metrics |
|---|---|
| Infrastructure | CPU, memory, disk usage, network traffic, system load |
| Web server | Request rate, error rate, latency (via Nginx Exporter and ALB metrics) |
| Database | RDS connections, read/write latency, CPU utilization |
| Load balancer | Request count, response time p99, healthy host count |

See `monitoring/prometheus/alerts.yml` for the full alert rule list (CPU, memory, disk, instance down, ALB error rate, and more).

---

## Logging

Logs from both EC2 instances are shipped via Filebeat to a local ELK stack through an SSM reverse tunnel:

```bash
aws ssm start-session --target <instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["localhost"],"portNumber":["5044"],"localPortNumber":["5044"]}'
```

Start the local stack:

```bash
docker compose -f logging/docker-compose.logging.yml up -d
```

Kibana is available at `http://localhost:5601`. Create a data view with index pattern `drupal-logs-*` and timestamp field `@timestamp`.

---

## CI/CD Pipeline

GitHub Actions runs a five-job pipeline on every push:

1. **build** — builds the Docker image, pushes to ECR
2. **test** — runs PHP syntax checks and integration tests against `/health` and the homepage
3. **deploy-staging** — deploys to one EC2 instance via SSM (main branch only)
4. **smoke-test-staging** — verifies the ALB health check, homepage, and login page all return 200
5. **deploy-production** — requires manual approval in the GitHub Environment, then deploys to all instances

Authentication uses OIDC federation. The only GitHub secret required is `AWS_ROLE_ARN`, no static AWS keys are stored.

To set up the OIDC provider and IAM role:

```bash
./scripts/setup-github-oidc.sh
```

---

## Security Design

- No SSH keys, no bastion host, port 22 closed to the internet
- No long-lived AWS credentials in CI/CD (OIDC federation only, token expires at end of each run)
- Least-privilege IAM roles for both EC2 instances and GitHub Actions
- Three-tier network segmentation: public (ALB only), private (app servers), database (RDS only, no internet access)
- RDS has no public access and is reachable only from the app security group on port 3306
- S3 bucket blocks all public access, with versioning and AES256 encryption enabled

---

## Cost Profile

Approximate monthly cost if left running:

| Item | Cost |
|---|---|
| 2x NAT Gateways (one per AZ) | ~$32/month |
| 1x Application Load Balancer | ~$8/month |
| 1x RDS read replica | ~$4/month |
| 2x EC2 t2.micro | Free tier |
| 1x RDS db.t3.micro primary | Free tier |
| S3 storage | Negligible |

**Run `terraform destroy` as soon as you're done to stop billing.** CloudWatch billing alarms are set at 50% and 90% of a $50/month budget.

To reduce cost in non-production use: drop to a single NAT Gateway (accepts a single point of failure on outbound traffic) or remove the RDS read replica.

---

## Troubleshooting

A full list of 20 resolved incidents with root causes is in [`docs/`](docs/). A few worth knowing before you start:

| Symptom | Cause | Fix |
|---|---|---|
| `terraform apply` fails on S3 lifecycle rule | AWS provider requires an explicit empty `filter {}` block | Add the empty filter block |
| Corrupted userdata after `terraform apply` | `templatefile()` uses `${VAR}` syntax which collides with Bash | Use `file()` instead, or escape with `$$` in Bash |
| Invalid CIDR error | Trailing whitespace in `terraform.tfvars` | Trim the value |
| `/health` returns 404 after Ansible completes successfully | Nginx reloads (not restarts) before the Drupal role creates the document root, leaving stale workers | Playbook runs unconditional Nginx/PHP-FPM restarts as `post_tasks` |
| `Table users_data already exists` during Drupal install | Both EC2 instances share one RDS database and both tried to run `site:install` | Already handled by the `when:` condition in the `drupal` role, see [Configuration](#configuration) |
| `web/index.php` missing after Composer install | Composer skips plugin execution (including scaffolding) when run as root without explicit permission | Set `COMPOSER_ALLOW_SUPERUSER=1` |
| ECR push fails with `AccessDeniedException` | IAM policy used only a wildcard ARN pattern | Include both the exact repository ARN and the wildcard pattern |
| CloudWatch Exporter returns only `RequestCount`, no RDS/latency metrics | `p99` was listed under `aws_statistics` instead of `aws_extended_statistics` | Move `p99` to `aws_extended_statistics` |
| ALB stops routing, `ERR_CONNECTION_REFUSED` | Security group ingress block combined `cidr_blocks` and `self=true`, which AWS silently rejects | Split into two separate ingress blocks |
| Ansible requires venv activation every new terminal | `boto3`/`botocore` installed only in a virtualenv | Install at system level: `sudo pip3 install ansible boto3 botocore --break-system-packages` |
| Prometheus alert rule template errors | Ansible's Jinja2 tries to parse Prometheus's `{{ }}` label syntax | Wrap in `{% raw %}` / `{% endraw %}` |
| Kind ingress controller stuck in `ContainerCreating` | `ingress-nginx` main branch targets newer Kubernetes versions | Pin to `controller-v1.12.2`; load images with `docker save` + `docker exec ctr import` on WSL2/Docker Desktop |

---

## Contributing

1. Fork the repository and create a feature branch from `main`.
2. Make your changes. If you touch Terraform, run `terraform plan` and include the output in your PR description.
3. If you touch Ansible roles, confirm the playbook still runs with `failed=0` on a test instance.
4. Open a pull request against `main`. The CI pipeline runs build and test jobs automatically; both must pass.
5. Deployment to staging happens automatically once tests pass. Production deployment requires manual approval from a repository maintainer, you do not need to do anything extra here.
6. Keep documentation in sync: if you fix a bug worth knowing about, add it to the troubleshooting log in `docs/` with symptom, root cause, and fix, following the existing format.

### Code Style

- Terraform: keep resources organized into modules under `terraform/modules/`, do not put resources directly in the environment root unless they are genuinely environment-specific
- Ansible: roles should remain idempotent, re-running `site.yml` must not break a working deployment
- Commit messages: describe the change and, where relevant, the AWS/infra impact (e.g. "Fix ALB security group rule conflict, no new resources created")

---

## License

Not specified. You can reuse in another project.
