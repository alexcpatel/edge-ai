# Data source for Ubuntu 22.04 LTS AMI (official Canonical AMI)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group
resource "aws_security_group" "yocto_builder" {
  name        = "yocto-builder-sg"
  description = "Security group for Yocto builder EC2 instance - allows SSH access"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "yocto-builder-sg"
  }

  lifecycle {
    ignore_changes = [
      ingress,
      egress,
      tags,
      tags_all,
      revoke_rules_on_delete
    ]
  }
}

# EC2 Instance
resource "aws_instance" "yocto_builder" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  key_name             = var.instance_key_name
  subnet_id            = var.instance_subnet_id
  iam_instance_profile = aws_iam_instance_profile.yocto_builder.name

  vpc_security_group_ids = [aws_security_group.yocto_builder.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 200
    iops                  = 3000
    throughput            = 125
    encrypted             = false
    delete_on_termination = true
  }

  tags = {
    Name = var.instance_name
  }

  # Prevent Terraform from making changes to running instance
  # Note: ami and instance_type are not ignored to allow architecture changes
  lifecycle {
    ignore_changes = [
      user_data,
      vpc_security_group_ids,
      root_block_device
    ]
  }
}

