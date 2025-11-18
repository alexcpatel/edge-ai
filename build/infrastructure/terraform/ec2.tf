# Security Group
# This resource matches the existing security group and will be imported
resource "aws_security_group" "yocto_builder" {
  name        = "launch-wizard-2"
  description = "launch-wizard-2 created 2025-11-11T02:45:31.839Z"
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
      name,
      description,
      ingress,
      egress,
      tags,
      tags_all,
      revoke_rules_on_delete
    ]
  }
}

# EC2 Instance
# This resource matches the existing instance and will be imported
resource "aws_instance" "yocto_builder" {
  ami           = var.instance_ami
  instance_type = var.instance_type
  key_name      = var.instance_key_name
  subnet_id     = var.instance_subnet_id

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

