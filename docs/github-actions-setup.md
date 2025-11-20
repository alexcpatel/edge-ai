# GitHub Actions Setup Guide

This guide explains how to set up secure GitHub Actions workflows that build Yocto images on EC2 without using access keys or sharing SSH private keys.

## Security Features

- **OIDC Authentication**: Uses AWS IAM roles with OpenID Connect (OIDC) instead of access keys
- **EC2 Instance Connect**: Uses temporary SSH keys via EC2 Instance Connect API instead of permanent private keys

## Prerequisites

1. AWS account with appropriate permissions
2. Terraform configured and ready to apply
3. GitHub repository

## Setup Steps

### 1. Update Terraform Variables

Add your GitHub repository to `terraform.tfvars`:

```hcl
github_repository = "your-org/edge-ai"  # Replace with your actual repo
```

### 2. Apply Terraform Changes

```bash
cd build/infrastructure/terraform
terraform init
terraform plan
terraform apply
```

This will create:

- OIDC provider for GitHub Actions
- IAM role for GitHub Actions with necessary permissions
- EC2 Instance Connect permissions

### 3. Get the IAM Role ARN

After applying Terraform, get the role ARN:

```bash
terraform output github_actions_role_arn
```

### 4. Configure GitHub Secret

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `AWS_ROLE_ARN`
5. Value: Paste the ARN from step 3 (e.g., `arn:aws:iam::123456789012:role/yocto-builder-github-actions-role`)

### 5. Verify EC2 Instance Connect

The EC2 instance should have EC2 Instance Connect enabled by default on Ubuntu 22.04. To verify:

```bash
# SSH into your instance (using your local key)
make instance-ssh

# Check if ec2-instance-connect is installed
dpkg -l | grep ec2-instance-connect
```

If it's not installed, install it:

```bash
sudo apt-get update
sudo apt-get install -y ec2-instance-connect
```

## How It Works

### OIDC Authentication

GitHub Actions uses OIDC to assume the IAM role. No access keys are stored in GitHub Secrets.

1. GitHub generates an OIDC token
2. AWS validates the token
3. AWS grants temporary credentials based on the IAM role

### EC2 Instance Connect

Instead of using permanent SSH keys:

1. GitHub Actions generates a temporary SSH key pair
2. Sends the public key to EC2 via the Instance Connect API
3. Uses the temporary private key for SSH (valid for 60 seconds)
4. Automatically cleans up the temporary key

## Troubleshooting

### Workflow fails with "Failed to assume role"

- Verify the `AWS_ROLE_ARN` secret is set correctly
- Check that the GitHub repository name in Terraform matches your actual repo
- Ensure the OIDC provider was created successfully

### SSH connection fails

- Verify EC2 Instance Connect is installed on the instance
- Check that the IAM role has `ec2-instance-connect:SendSSHPublicKey` permission
- Ensure the instance is running

### Permission denied errors

- Verify the IAM role has all necessary EC2 permissions
- Check that the instance ID matches the one in your Terraform state

## Local Development

All scripts now use EC2 Instance Connect for SSH authentication, both locally and in CI/CD. This means:

- **No SSH private keys needed** - Your laptop uses the same authentication method as GitHub Actions
- **Simpler setup** - Just ensure your AWS credentials are configured (via `aws configure` or environment variables)
- **More secure** - Temporary keys are generated on-demand and automatically cleaned up

### Local IAM Permissions

For local development, your AWS credentials (IAM user or role) need the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:DescribeInstanceAttribute"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2-instance-connect:SendSSHPublicKey"
      ],
      "Resource": "arn:aws:ec2:REGION:ACCOUNT:instance/i-*",
      "Condition": {
        "StringEquals": {
          "ec2:osuser": "ubuntu"
        }
      }
    }
  ]
}
```

Replace `REGION` and `ACCOUNT` with your actual AWS region and account ID. You can attach this policy to your IAM user or create a role for local development.
