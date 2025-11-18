#!/bin/bash
# Script to import existing AWS resources into Terraform
# Run this after 'terraform init' and before 'terraform plan'
#
# Usage: ./import.sh

set -e

INSTANCE_ID="i-06f80357488b47d10"
SECURITY_GROUP_ID="sg-0592d376e80a9cbed"

echo "Importing security group..."
terraform import aws_security_group.yocto_builder "$SECURITY_GROUP_ID"

echo "Importing EC2 instance..."
terraform import aws_instance.yocto_builder "$INSTANCE_ID"

echo ""
echo "Import complete! Run 'terraform plan' to verify no changes are detected."
echo "The resources are now tracked in Terraform state but won't be modified."

