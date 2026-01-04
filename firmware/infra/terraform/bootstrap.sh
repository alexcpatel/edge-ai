#!/bin/bash
set -euo pipefail

REGION="us-east-2"
STATE_BUCKET="yocto-builder-terraform-state"
LOCK_TABLE="terraform-state-lock"

echo "Creating S3 bucket for Terraform state..."
aws s3 mb "s3://${STATE_BUCKET}" --region "${REGION}"

echo "Creating DynamoDB table for state locking..."
aws dynamodb create-table \
  --table-name "${LOCK_TABLE}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${REGION}"

echo "Waiting for DynamoDB table to be active..."
aws dynamodb wait table-exists --table-name "${LOCK_TABLE}" --region "${REGION}"

echo "Initializing Terraform..."
terraform init

echo "Bootstrap complete. Run 'terraform apply' to create infrastructure."
