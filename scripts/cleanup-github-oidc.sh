#!/bin/bash
# ============================================================
# GitHub Actions OIDC Cleanup
# Removes the IAM role and inline policy created by setup script.
# Does NOT remove the OIDC provider since it is shared across
# all roles in your account. Remove it manually if you are
# sure nothing else uses it.
# ============================================================
set -euo pipefail

ROLE_NAME="github-actions-drupal-role"
POLICY_NAME="github-actions-drupal-policy"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Removing inline policy from role..."
aws iam delete-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" 2>/dev/null || echo "Policy not found, skipping"

echo "Deleting IAM role..."
aws iam delete-role \
  --role-name "$ROLE_NAME" 2>/dev/null || echo "Role not found, skipping"

echo ""
echo "Cleanup complete."
echo ""
echo "NOTE: The OIDC provider was NOT removed."
echo "If no other roles use it, remove it manually with:"
echo ""
echo "  aws iam delete-open-id-connect-provider \\"
echo "    --open-id-connect-provider-arn arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
