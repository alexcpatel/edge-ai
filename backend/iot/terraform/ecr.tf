# ECR Repository for Edge AI containers
# All production images must be signed with Cosign + KMS

resource "aws_ecr_repository" "edge_ai" {
  name                 = "edge-ai"
  image_tag_mutability = "IMMUTABLE" # Tags can't be overwritten

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = {
    Purpose = "edge-ai-containers"
  }
}

# Lifecycle policy - keep last 10 images per tag pattern
resource "aws_ecr_lifecycle_policy" "edge_ai" {
  repository = aws_ecr_repository.edge_ai.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# IAM policy for pushing to ECR (developers/CI)
resource "aws_iam_policy" "ecr_push" {
  name        = "edge-ai-ecr-push"
  description = "Allows pushing container images to ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = aws_ecr_repository.edge_ai.arn
      }
    ]
  })
}

# IAM policy for devices to pull from ECR
resource "aws_iam_policy" "ecr_pull" {
  name        = "edge-ai-ecr-pull"
  description = "Allows devices to pull container images from ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = aws_ecr_repository.edge_ai.arn
      }
    ]
  })
}

# Store ECR URL in SSM for device provisioning
resource "aws_ssm_parameter" "ecr_url" {
  name        = "/edge-ai/ecr/repository-url"
  description = "ECR repository URL for edge containers"
  type        = "String"
  value       = aws_ecr_repository.edge_ai.repository_url

  tags = {
    Purpose = "container-registry"
  }
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.edge_ai.repository_url
  description = "ECR repository URL"
}

