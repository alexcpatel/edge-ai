# Container Signing Infrastructure
# KMS key for signing container images, public key distributed to devices

# KMS key for container signing (asymmetric - private key never leaves KMS)
resource "aws_kms_key" "container_signing" {
  description              = "Edge AI container signing key"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 30

  tags = {
    Name    = "edge-ai-container-signing"
    Purpose = "container-signing"
  }
}

resource "aws_kms_alias" "container_signing" {
  name          = "alias/edge-container-signing"
  target_key_id = aws_kms_key.container_signing.key_id
}

# IAM policy for developers/CI to sign containers
resource "aws_iam_policy" "container_signer" {
  name        = "edge-ai-container-signer"
  description = "Allows signing container images with KMS key"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Sign",
          "kms:GetPublicKey"
        ]
        Resource = aws_kms_key.container_signing.arn
      }
    ]
  })
}

# Store public key in SSM for device provisioning
# The public key is extracted and stored as a parameter
resource "aws_ssm_parameter" "container_signing_public_key" {
  name        = "/edge-ai/pki/container-signing-public-key"
  description = "Public key for container signature verification"
  type        = "String"
  # This will be populated by a null_resource that extracts the public key
  value = "PLACEHOLDER"

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Purpose = "container-signing"
  }
}

# Extract and store the public key
resource "null_resource" "extract_public_key" {
  depends_on = [aws_kms_key.container_signing]

  provisioner "local-exec" {
    command = <<-EOT
      aws kms get-public-key \
        --key-id ${aws_kms_key.container_signing.key_id} \
        --region ${data.aws_region.current.name} \
        --output text \
        --query PublicKey | base64 -d > /tmp/container-signing.der

      openssl ec -pubin -inform DER -in /tmp/container-signing.der -outform PEM -out /tmp/container-signing.pub

      aws ssm put-parameter \
        --name "/edge-ai/pki/container-signing-public-key" \
        --value "$(cat /tmp/container-signing.pub)" \
        --type String \
        --overwrite \
        --region ${data.aws_region.current.name}

      rm -f /tmp/container-signing.der /tmp/container-signing.pub
    EOT
  }

  triggers = {
    key_id = aws_kms_key.container_signing.key_id
  }
}

# Output for reference
output "container_signing_key_id" {
  value       = aws_kms_key.container_signing.key_id
  description = "KMS key ID for container signing"
}

output "container_signing_key_alias" {
  value       = aws_kms_alias.container_signing.name
  description = "KMS key alias for container signing"
}

