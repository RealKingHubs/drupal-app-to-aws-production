#!/bin/bash
# ============================================================
# GitHub Actions OIDC Setup
# Creates an IAM role that GitHub Actions assumes via OIDC.
# No long-lived keys. Role is scoped to only what the
# drupal-app-to-aws-production pipeline actually needs.
#
# Run once before the pipeline, then destroy with cleanup.sh
# ============================================================
set -euo pipefail

GITHUB_ORG="RealKingHubs"
GITHUB_REPO="drupal-app-to-aws-production"
ROLE_NAME="github-actions-drupal-role"
POLICY_NAME="github-actions-drupal-policy"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Account: $ACCOUNT_ID"
echo "Setting up OIDC for $GITHUB_ORG/$GITHUB_REPO"

# ============================================================
# Step 1: Create the GitHub OIDC provider (only one per account)
# Skip if it already exists
# ============================================================
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>/dev/null; then
  echo "OIDC provider already exists, skipping creation"
else
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null 2>/dev/null
  echo "OIDC provider created"
fi

# ============================================================
# Step 2: Create the trust policy
# Scoped to only this specific repo and branch pattern
# StringLike allows main branch and pull requests
# ============================================================
TRUST_POLICY="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\",\"Condition\":{\"StringLike\":{\"token.actions.githubusercontent.com:sub\":\"repo:${GITHUB_ORG}/${GITHUB_REPO}:*\"},\"StringEquals\":{\"token.actions.githubusercontent.com:aud\":\"sts.amazonaws.com\"}}}]}"

# ============================================================
# Step 3: Create the IAM role
# ============================================================
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>/dev/null; then
  echo "Role already exists, updating trust policy"
  aws iam update-assume-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-document "$TRUST_POLICY"
else
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --description "GitHub Actions role for drupal-app-to-aws-production. Least privilege." >/dev/null
  echo "Role created"
fi

# ============================================================
# Step 4: Create a least-privilege inline policy
# Includes both strict 'drupal-app' and wildcard variants
# ============================================================
PERMISSIONS_POLICY="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"ECRAuth\",\"Effect\":\"Allow\",\"Action\":[\"ecr:GetAuthorizationToken\"],\"Resource\":\"*\"},{\"Sid\":\"ECRPush\",\"Effect\":\"Allow\",\"Action\":[\"ecr:BatchCheckLayerAvailability\",\"ecr:GetDownloadUrlForLayer\",\"ecr:BatchGetImage\",\"ecr:InitiateLayerUpload\",\"ecr:UploadLayerPart\",\"ecr:CompleteLayerUpload\",\"ecr:PutImage\",\"ecr:CreateRepository\",\"ecr:DescribeRepositories\"],\"Resource\":[\"arn:aws:ecr:us-east-1:${ACCOUNT_ID}:repository/drupal-app\",\"arn:aws:ecr:us-east-1:${ACCOUNT_ID}:repository/drupal-app*\"]},{\"Sid\":\"EC2Describe\",\"Effect\":\"Allow\",\"Action\":[\"ec2:DescribeInstances\",\"ec2:DescribeTags\"],\"Resource\":\"*\"},{\"Sid\":\"SSMConnect\",\"Effect\":\"Allow\",\"Action\":[\"ssm:StartSession\",\"ssm:SendCommand\",\"ssm:GetCommandInvocation\",\"ssm:DescribeInstanceInformation\",\"ssm:TerminateSession\"],\"Resource\":[\"arn:aws:ec2:us-east-1:${ACCOUNT_ID}:instance/*\",\"arn:aws:ssm:us-east-1:${ACCOUNT_ID}:*\",\"arn:aws:ssm:us-east-1::document/AWS-RunShellScript\"]},{\"Sid\":\"ALBHealthCheck\",\"Effect\":\"Allow\",\"Action\":[\"elasticloadbalancing:DescribeTargetHealth\",\"elasticloadbalancing:DescribeTargetGroups\",\"elasticloadbalancing:DescribeLoadBalancers\"],\"Resource\":\"*\"},{\"Sid\":\"S3Artifacts\",\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"s3:ListBucket\"],\"Resource\":[\"arn:aws:s3:::drupal-aws-production-files-*\",\"arn:aws:s3:::drupal-aws-production-files-*/*\"]},{\"Sid\":\"CloudWatchMetrics\",\"Effect\":\"Allow\",\"Action\":[\"cloudwatch:PutMetricData\"],\"Resource\":\"*\"}]}"

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document "$PERMISSIONS_POLICY"

echo ""
echo "Done. Add this to your GitHub Actions workflow:"
echo ""
echo "  role-to-assume: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "  aws-region: us-east-1"
echo ""
echo "Add this to your repo secrets:"
echo "  AWS_ROLE_ARN = arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
