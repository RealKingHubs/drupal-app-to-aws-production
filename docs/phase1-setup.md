# Phase 1 Setup Guide - Terraform Infrastructure

## Architecture summary

| Component | Spec | Cost behavior |
|---|---|---|
| VPC | 2 AZs (us-east-1a, us-east-1b) | Free |
| Subnets | Public, private, database x2 each | Free |
| NAT Gateways | 1 per AZ (2 total) | ~$1.08/day each, ~$2.16/day total |
| ALB | 1, across both public subnets | ~$0.54/day + LCU usage |
| ASG | t2.micro, min 2 / desired 2 / max 4 | Free up to 750 hrs/month total |
| RDS Primary | db.t2.micro, single-AZ, us-east-1a | Free up to 750 hrs/month |
| RDS Replica | db.t2.micro, us-east-1b | NOT free, ~$0.27/day |
| S3 | Drupal files, versioned | Free under 5GB |
| Billing Alarm | SNS email at 50% and 90% of budget | Free |

**Estimated cost for 15 days: ~$40-44 total.**

---

## Before you run anything

### 1. Create the Terraform state backend (one-time)

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws s3api create-bucket \
  --bucket "drupal-aws-tfstate-${AWS_ACCOUNT_ID}" \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket "drupal-aws-tfstate-${AWS_ACCOUNT_ID}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "drupal-aws-tfstate-${AWS_ACCOUNT_ID}" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

aws dynamodb create-table \
  --table-name drupal-aws-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Update the `main.tf` backend block with your real bucket name (replace `YOUR_ACCOUNT_ID`).

### 2. Create an EC2 key pair

```bash
aws ec2 create-key-pair \
  --key-name drupal-aws-key \
  --region us-east-1 \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/drupal-aws-key.pem

chmod 400 ~/.ssh/drupal-aws-key.pem
```

### 3. Find your IP address for the security group

```bash
curl https://checkip.amazonaws.com
```

Add `/32` to the end, for example `203.0.113.45/32`.

### 4. Fill in terraform.tfvars

Edit `terraform/environments/production/terraform.tfvars` and set:
- `ec2_key_name` - the key pair you just created
- `admin_ip_cidr` - your IP from step 3
- `db_password` - strong password, 16+ characters
- `billing_alert_email` - your real email, alarm notifications go here
- `budget_limit_usd` - default is 50, adjust if needed

### 5. Confirm the SNS email subscription

After `terraform apply`, AWS sends a confirmation email to `billing_alert_email`. You must click confirm or you will not receive billing alerts.

---

## Run Terraform

```bash
cd terraform/environments/production
terraform init
terraform plan -out=tfplan.out
terraform apply tfplan.out
```

Takes about 10-15 minutes. The RDS replica creation is the longest step.

---

## Verify everything

```bash
# Get the site URL
terraform output alb_dns_name

# Check both RDS instances
aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,AvailabilityZone]' \
  --output table

# Confirm billing alarms are active
aws cloudwatch describe-alarms \
  --alarm-name-prefix "drupal-aws-production-billing"

# Check ASG instance count
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "drupal-aws-production-asg" \
  --query 'AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize,Instances[*].HealthStatus]'
```

---

## CRITICAL: cost safety checklist

- [ ] Confirmed the SNS billing alert email subscription
- [ ] `asg_max_size` is set to 4, not higher
- [ ] You know how to run `terraform destroy` when done
- [ ] You are checking the AWS Billing dashboard every few days during the project
- [ ] You have noted the start date so you know how many days you have been running

---

## When you are done documenting - DESTROY EVERYTHING

```bash
cd terraform/environments/production
terraform destroy
```

Type `yes` when prompted. This removes:
- Both NAT Gateways (stops the biggest cost immediately)
- The ALB
- Both RDS instances
- The ASG and its EC2 instances
- The S3 bucket (only if empty - empty it first if needed)

Verify nothing is left:
```bash
aws ec2 describe-instances --filters "Name=tag:Project,Values=drupal-aws" --query 'Reservations[*].Instances[*].State.Name'
aws rds describe-db-instances --query 'DBInstances[*].DBInstanceIdentifier'
aws ec2 describe-nat-gateways --filter "Name=tag:Project,Values=drupal-aws"
```

All should return empty once destroy completes.

---

## Next step

Once `terraform apply` succeeds and the ALB DNS name resolves, save your outputs and move to Phase 2 (Ansible):

```bash
terraform output > ../../../docs/terraform-outputs.txt
```
