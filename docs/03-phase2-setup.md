# Phase 2 Setup Guide - Ansible Configuration

## What this phase does

Installs Nginx, PHP-FPM, and Drupal 10 on both app servers via Ansible,
connects them to the RDS primary database, sets up the `/health` endpoint
the ALB checks, and configures rsync-based file sync between the two
servers (since we are not using EFS).

By the end of this phase, your ALB target group should show both instances
as healthy, and the 502 error becomes a working Drupal site.

---

## Install Ansible Galaxy collections

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

## Confirm Session Manager plugin is installed in WSL

```bash
session-manager-plugin
```

This should print version info. If it's missing:

```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
```

---

## Fill in your variables

Edit `group_vars/all.yml` and replace every `CHANGE_ME`.

Get your RDS endpoint:
```bash
cd ../terraform/environments/production
terraform output -raw rds_primary_endpoint
```

The output looks like `drupal-aws-production-mysql-primary-xxxx.xxxxx.us-east-1.rds.amazonaws.com:3306`.
Use only the part before the colon as `drupal_db_host`.

Get your S3 bucket name:
```bash
terraform output s3_bucket_name
```

Set `drupal_db_password` to match exactly what you set in `terraform.tfvars`
for `db_password`. Set `drupal_admin_password` to a new password for the
Drupal admin login (this is separate from the database password).

---

## Test connectivity before running the full playbook

### 1. Confirm Ansible can see your instances via dynamic inventory

```bash
cd ../../../ansible
ansible-inventory -i inventory/aws_ec2.yml --list
```

You should see both EC2 instance IDs listed under the `tag_drupal_aws_production_app` group.

### 2. Confirm SSM connectivity works

```bash
ansible all -i inventory/aws_ec2.yml -m ping
```

This should return `pong` for both hosts.

### 3. Test database connectivity from the app servers

```bash
ansible-playbook test-db-connection.yml
```

This confirms the security groups and credentials are correct before
attempting the full Drupal install.

---

## Run the main playbook

```bash
ansible-playbook site.yml
```

This takes 10-15 minutes per server (Composer downloading Drupal is the
slowest part). Watch for the final health check task at the end.

---

## Verify from outside

```bash
cd ../terraform/environments/production
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)
```

Both targets should now show `"State": "healthy"`.

Then open the ALB DNS name in your browser:
```bash
terraform output alb_dns_name
```

You should see the Drupal installation/welcome page instead of a 502.

---

## IMPORTANT: switch ASG health check back to ELB

Now that the app is actually responding to `/health`, switch the ASG back
to checking real application health.

**File:** `terraform/modules/asg/main.tf`

Change:
```hcl
health_check_type = "EC2"
```
back to:
```hcl
health_check_type = "ELB"
```

Then:
```bash
terraform plan -out=tfplan.out
terraform apply tfplan.out
```

---

## Troubleshooting

**Ansible hangs on "Wait for SSM connectivity"**
Check the instance has had at least 2-3 minutes to fully boot and start
the SSM agent.

**Drush site:install fails with a database error**
Run `test-db-connection.yml` first to isolate whether it's a credentials
issue or a network/security group issue.

**Composer create-project times out**
This can happen on a t2.micro under memory pressure. Re-run the playbook,
Ansible's `creates:` check means it will not redo completed work.
