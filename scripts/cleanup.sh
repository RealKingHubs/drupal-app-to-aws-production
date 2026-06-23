#!/bin/bash
set -e

# Configuration (Matches the creation script)
REGION="us-east-1"
LOCK_TABLE="drupal-aws-tfstate-lock"
KEY_NAME="drupal-aws-key"
KEY_FILE="drupal-aws-key.pem"

echo "Connecting to AWS..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_ACCOUNT_ID=$(echo "$AWS_ACCOUNT_ID" | tr -d '\r') # Strip Windows line endings
BUCKET_NAME="drupal-aws-tfstate-${AWS_ACCOUNT_ID}"

echo -e "\n========================================="
echo "      CLEANING UP AWS INFRASTRUCTURE"
echo "========================================="

echo "-> Deleting DynamoDB Lock Table..."
aws dynamodb delete-table --table-name "${LOCK_TABLE}" --region "${REGION}" 2>/dev/null || echo "   DynamoDB table already deleted."

echo "-> Deleting EC2 Key Pair from AWS..."
aws ec2 delete-key-pair --key-name "${KEY_NAME}" --region "${REGION}" 2>/dev/null || echo "   AWS Key pair already deleted."

echo "-> Removing local private key file (${KEY_FILE})..."
rm -f "${KEY_FILE}"

echo "-> Checking S3 Bucket status..."
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "   Emptying S3 object versions (required for versioned buckets)..."
  VERSIONS=$(aws s3api list-object-versions --bucket "${BUCKET_NAME}" --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' --output json)
  if [ "$VERSIONS" != "null" ] && [ ! -z "$VERSIONS" ]; then
    aws s3api delete-objects --bucket "${BUCKET_NAME}" --delete "$VERSIONS" 2>/dev/null || true
  fi

  echo "   Emptying S3 delete markers..."
  MARKERS=$(aws s3api list-object-versions --bucket "${BUCKET_NAME}" --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' --output json)
  if [ "$MARKERS" != "null" ] && [ ! -z "$MARKERS" ]; then
    aws s3api delete-objects --bucket "${BUCKET_NAME}" --delete "$MARKERS" 2>/dev/null || true
  fi

  echo "-> Deleting S3 Bucket..."
  aws s3api delete-bucket --bucket "${BUCKET_NAME}" --region "${REGION}"
else
  echo "   S3 Bucket does not exist or has already been deleted."
fi

echo -e "\n========================================="
echo -e "\033[1;31mCLEANUP COMPLETE. ALL RESOURCES REMOVED.\033[0m"
echo "========================================="
