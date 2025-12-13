# AWS IoT Fleet Provisioning for zero-touch device registration
# Uses claim certificates baked into rootfs to bootstrap device identity

# IAM Role for Fleet Provisioning
resource "aws_iam_role" "fleet_provisioning" {
  name = "edge-ai-fleet-provisioning-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "iot.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "fleet_provisioning" {
  name = "edge-ai-fleet-provisioning-policy"
  role = aws_iam_role.fleet_provisioning.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:CreateThing",
          "iot:CreateCertificateFromCsr",
          "iot:RegisterCertificate",
          "iot:AttachThingPrincipal",
          "iot:AttachPolicy",
          "iot:DescribeThing",
          "iot:UpdateCertificate"
        ]
        Resource = "*"
      }
    ]
  })
}

# Pre-provisioning Lambda - cleans up old resources on re-flash
resource "aws_iam_role" "pre_provisioning_lambda" {
  name = "edge-ai-pre-provisioning-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "pre_provisioning_lambda" {
  name = "edge-ai-pre-provisioning-lambda-policy"
  role = aws_iam_role.pre_provisioning_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "iot:DescribeThing",
          "iot:DeleteThing",
          "iot:ListThingPrincipals",
          "iot:DetachThingPrincipal",
          "iot:DetachPolicy",
          "iot:ListAttachedPolicies",
          "iot:UpdateCertificate",
          "iot:DeleteCertificate"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "pre_provisioning" {
  function_name = "edge-ai-pre-provisioning-hook"
  role          = aws_iam_role.pre_provisioning_lambda.arn
  handler       = "pre_provisioning_hook.handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.pre_provisioning_lambda.output_path
  source_code_hash = data.archive_file.pre_provisioning_lambda.output_base64sha256
}

data "archive_file" "pre_provisioning_lambda" {
  type        = "zip"
  source_file = "${path.module}/pre_provisioning_hook.py"
  output_path = "${path.module}/pre_provisioning_lambda.zip"
}

resource "aws_lambda_permission" "iot_invoke" {
  statement_id  = "AllowIoTInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_provisioning.function_name
  principal     = "iot.amazonaws.com"
}

# Fleet Provisioning Template
resource "aws_iot_provisioning_template" "device" {
  name                  = var.fleet_provisioning_template_name
  description           = "Fleet provisioning template for Edge AI devices"
  provisioning_role_arn = aws_iam_role.fleet_provisioning.arn
  enabled               = true

  pre_provisioning_hook {
    target_arn      = aws_lambda_function.pre_provisioning.arn
    payload_version = "2020-04-01"
  }

  template_body = jsonencode({
    Parameters = {
      SerialNumber = { Type = "String" }
      MacAddress   = { Type = "String", Default = "unknown" }
      ThingName    = { Type = "String" }
    }
    Resources = {
      thing = {
        Type = "AWS::IoT::Thing"
        Properties = {
          ThingName     = { Ref = "ThingName" }
          ThingTypeName = var.thing_type_name
          AttributePayload = {
            SerialNumber = { Ref = "SerialNumber" }
            MacAddress   = { Ref = "MacAddress" }
          }
        }
      }
      certificate = {
        Type = "AWS::IoT::Certificate"
        Properties = {
          CertificateId = { Ref = "AWS::IoT::Certificate::Id" }
          Status        = "ACTIVE"
        }
      }
      policy = {
        Type = "AWS::IoT::Policy"
        Properties = {
          PolicyName = var.policy_name
        }
      }
    }
  })
}

# Claim Certificate Policy - limited permissions for bootstrap only
resource "aws_iot_policy" "claim_cert" {
  name = "edge-ai-claim-cert-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iot:Connect"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["iot:Publish", "iot:Receive"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/$aws/certificates/create-from-csr/*",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/$aws/provisioning-templates/${var.fleet_provisioning_template_name}/provision/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["iot:Subscribe"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/$aws/certificates/create-from-csr/*",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/$aws/provisioning-templates/${var.fleet_provisioning_template_name}/provision/*"
        ]
      }
    ]
  })
}

# Create claim certificate for fleet provisioning
resource "aws_iot_certificate" "claim" {
  active = true
}

# Attach claim cert policy
resource "aws_iot_policy_attachment" "claim_cert" {
  policy = aws_iot_policy.claim_cert.name
  target = aws_iot_certificate.claim.arn
}

# Get IoT endpoint
data "aws_iot_endpoint" "ats" {
  endpoint_type = "iot:Data-ATS"
}


