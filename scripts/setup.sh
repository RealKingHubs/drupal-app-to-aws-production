#!/bin/bash
set -e

# Configuration
REGION="us-east-1"
LOCK_TABLE="drupal-aws-tfstate-lock"
KEY_NAME="drupal-aws-key"
KEY_FILE="drupal-aws-key.pem"

echo "Connecting to AWS..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_ACCOUNT_ID=$(echo "$AWS_ACCOUNT_ID" | tr -d '\r') # Strip Windows line endings
BUCKET_NAME="drupal-aws-tfstate-${AWS_ACCOUNT_ID}"

echo -e "\n========================================="
echo "      CREATING AWS INFRASTRUCTURE"
echo "========================================="

echo "-> Creating S3 Bucket: ${BUCKET_NAME}"
aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}"

echo "-> Enabling Bucket Versioning..."
aws s3api put-bucket-versioning --bucket "${BUCKET_NAME}" --versioning-configuration Status=Enabled

echo "-> Enabling Default Encryption (AES256)..."
aws s3api put-bucket-encryption --bucket "${BUCKET_NAME}" --server-side-encryption-configuration '{
  "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
}'

echo "-> Creating DynamoDB Lock Table: ${LOCK_TABLE}"
aws dynamodb create-table \
  --table-name "${LOCK_TABLE}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${REGION}"

echo "-> Generating EC2 Key Pair: ${KEY_FILE}"
aws ec2 create-key-pair \
  --key-name "${KEY_NAME}" \
  --region "${REGION}" \
  --query 'KeyMaterial' \
  --output text > "${KEY_FILE}"

# Secure file permissions inside Git Bash environment
chmod 400 "${KEY_FILE}" 2>/dev/null || true

# CLEAR & VISUAL OUTPUT FOR THE USER
echo -e "\n========================================="
echo "       SUCCESS! DEPLOYMENT DETAILS"
echo "========================================="
echo -e "AWS Account ID:    \033[1;32m${AWS_ACCOUNT_ID}\033[0m"
echo -e "S3 Bucket Name:    \033[1;32m${BUCKET_NAME}\033[0m"
echo -e "DynamoDB Table:    \033[1;32m${LOCK_TABLE}\033[0m"
echo -e "SSH Key File:      \033[1;32m./${KEY_FILE}\033[0m"
echo -e "AWS Region:        \033[1;32m${REGION}\033[0m"
echo "========================================="
echo "Copy the block below directly into your main.tf file:"
echo "========================================="
cat <<EOF

terraform {
  backend "s3" {
    bucket         = "${BUCKET_NAME}"
    key            = "global/s3/terraform.tfstate"
    region         = "${REGION}"
    dynamodb_table = "${LOCK_TABLE}"
    encrypt        = true
  }
}

EOF
echo "========================================="
