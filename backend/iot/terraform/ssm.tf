# SSM Parameters for device configuration
# Parameters fetched at build time (claim certs) and runtime (NordVPN token)

resource "aws_ssm_parameter" "nordvpn_token" {
  name        = "/edge-ai/nordvpn-token"
  description = "NordVPN token for device meshnet access"
  type        = "SecureString"
  value       = "PLACEHOLDER_SET_VIA_CONSOLE"

  lifecycle {
    ignore_changes = [value]
  }
}

# Store claim certificate components in SSM for EC2 build access
resource "aws_ssm_parameter" "claim_cert" {
  name        = "/edge-ai/fleet-provisioning/claim-cert"
  description = "Fleet provisioning claim certificate (PEM)"
  type        = "SecureString"
  value       = aws_iot_certificate.claim.certificate_pem
}

resource "aws_ssm_parameter" "claim_key" {
  name        = "/edge-ai/fleet-provisioning/claim-key"
  description = "Fleet provisioning claim private key"
  type        = "SecureString"
  value       = aws_iot_certificate.claim.private_key
}

resource "aws_ssm_parameter" "claim_config" {
  name        = "/edge-ai/fleet-provisioning/config"
  description = "Fleet provisioning endpoint and template config"
  type        = "String"
  value = jsonencode({
    endpoint      = data.aws_iot_endpoint.ats.endpoint_address
    template_name = var.fleet_provisioning_template_name
  })
}
