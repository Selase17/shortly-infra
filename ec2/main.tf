# main.tf — EC2 instance running shortly (app + Redis) on a VPC

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Dynamically fetch the latest Amazon Linux 2023 AMI for this region.
# Never hardcode AMI IDs — they differ per region and change over time.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Network (VPC + public subnet + IGW + routing) ───────────────────

#tfsec:ignore:aws-ec2-require-vpc-flow-logs-for-all-vpcs -- accepted: learning project; flow logs noted as production enhancement
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name      = "${var.project_name}-vpc"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name      = "${var.project_name}-igw"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true  #tfsec:ignore:aws-ec2-no-public-ip-subnet -- intentional: no NAT gateway; demo requires direct public IP
  tags = {
    Name      = "${var.project_name}-public-subnet"
    Project   = var.project_name
    ManagedBy = "Terraform"
    Tier      = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name      = "${var.project_name}-public-rt"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Security group — the firewall for the instance ──────────────────
# Stateful: allowed inbound traffic's responses are auto-allowed back out.
# Default-deny: only what we list is permitted in.
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Allow HTTP to the shortly app"
  vpc_id      = aws_vpc.main.id

  # Inbound: allow HTTP on the app port from anywhere.
  ingress {
    description = "App HTTP"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-ingress-sgr -- intentional: public web app requires internet ingress
  }

  # Outbound: allow all (so the instance can pull Docker images, etc.)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  #tfsec:ignore:aws-ec2-no-public-egress-sgr -- intentional: instance needs internet access for Docker image pulls
  }

  tags = {
    Name      = "${var.project_name}-app-sg"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# ── EC2 instance ────────────────────────────────────────────────────
# t3.micro in the public subnet. user_data bootstraps Docker, then runs
# Redis + the shortly app as containers on first boot.
resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]


  # Enforce IMDSv2 — requires a token for all metadata requests.
  # Prevents SSRF attacks from stealing instance credentials via
  # the metadata endpoint (169.254.169.254).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"    # IMDSv2
    http_put_response_hop_limit = 1
  }


  root_block_device {
    encrypted = true
  }

  # user_data runs once, on first boot, as root.
  user_data = <<-EOF
    #!/bin/bash
    set -e
    # Install Docker on Amazon Linux 2023
    dnf update -y
    dnf install -y docker
    systemctl enable --now docker

    # Run Redis (shared state for the app)
    docker run -d --name redis --restart unless-stopped redis:7.4-alpine

    # Run the shortly app, pointing at the local Redis container.
    # --link is legacy; we use host networking simplicity here for a
    # single-host demo: app reaches redis via the container name on a
    # shared docker network.
    docker network create shortly-net || true
    docker rm -f redis || true
    docker run -d --name redis --network shortly-net --restart unless-stopped redis:7.4-alpine
    docker run -d --name shortly \
      --network shortly-net \
      -e REDIS_HOST=redis \
      -e REDIS_PORT=6379 \
      -p ${var.app_port}:5000 \
      --restart unless-stopped \
      ${var.app_image}
  EOF

  user_data_replace_on_change = true

  tags = {
    Name      = "${var.project_name}-app"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}