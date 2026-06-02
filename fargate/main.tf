
# main.tf — ECS Fargate deployment of shortly
#
# Contrast with ec2/: no AMI, no user-data, no Docker install.
# You describe the container; AWS runs it. The tradeoff: less control,
# less ops burden, billing per vCPU/memory-second while running.

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

# ── Network ──────────────────────────────────────────────────────────
# Same VPC pattern as ec2/ — public subnet, IGW, routing.
# Each Terraform root manages its own network; in a real setup you'd
# share a VPC via remote state references rather than duplicating it.

#tfsec:ignore:aws-ec2-require-vpc-flow-logs-for-all-vpcs -- accepted: learning project
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name      = "${var.project_name}-fargate-vpc"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name      = "${var.project_name}-fargate-igw"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true  #tfsec:ignore:aws-ec2-no-public-ip-subnet -- intentional: no NAT gateway; Fargate needs public IP for image pulls
  tags = {
    Name      = "${var.project_name}-fargate-public-subnet"
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
    Name      = "${var.project_name}-fargate-public-rt"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Security groups ───────────────────────────────────────────────────
# One for the app task, one for Redis task.
# They reference each other: app can reach Redis on 6379;
# Redis only accepts traffic from the app SG (not the whole world).

resource "aws_security_group" "app" {
  name        = "${var.project_name}-fargate-app-sg"
  description = "Allow HTTP inbound to the shortly app task"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  #tfsec:ignore:aws-ec2-no-public-ingress-sgr -- intentional: public web app
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  #tfsec:ignore:aws-ec2-no-public-egress-sgr -- intentional: Fargate needs internet for image pulls
  }

  tags = {
    Name      = "${var.project_name}-fargate-app-sg"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_security_group" "redis" {
  name        = "${var.project_name}-fargate-redis-sg"
  description = "Allow Redis traffic from the app task only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from app SG only"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  #tfsec:ignore:aws-ec2-no-public-egress-sgr -- intentional: Fargate needs internet for image pulls
  }

  tags = {
    Name      = "${var.project_name}-fargate-redis-sg"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# ── CloudWatch log groups ─────────────────────────────────────────────
# Fargate tasks send logs to CloudWatch. We create the log groups
# explicitly so Terraform manages (and destroys) them cleanly.

#tfsec:ignore:aws-cloudwatch-log-group-customer-key -- accepted: AWS-managed encryption sufficient for 1-day retention learning logs
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}/app"
  retention_in_days = 1 # minimal retention — learning project
  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

#tfsec:ignore:aws-cloudwatch-log-group-customer-key -- accepted: AWS-managed encryption sufficient for 1-day retention learning logs
resource "aws_cloudwatch_log_group" "redis" {
  name              = "/ecs/${var.project_name}/redis"
  retention_in_days = 1
  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# ── IAM role for ECS task execution ──────────────────────────────────
# Fargate needs permission to pull images from ECR and write logs to
# CloudWatch. This role is assumed by the ECS agent (not your app code).

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── ECS cluster ───────────────────────────────────────────────────────
# With Fargate, the cluster is just a logical namespace — no EC2 nodes
# to provision or manage. AWS handles all the underlying compute.

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# ── Redis task definition ─────────────────────────────────────────────
# A task definition is the blueprint for a container — image, CPU,
# memory, ports, env vars, logging. Think: Kubernetes pod spec.

resource "aws_ecs_task_definition" "redis" {
  family                   = "${var.project_name}-redis"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "redis"
    image     = "redis:7.4-alpine"
    essential = true
    portMappings = [{
      containerPort = 6379
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.redis.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "redis"
      }
    }
  }])

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# ── Redis ECS service ─────────────────────────────────────────────────
# A service keeps the task running and restarts it if it dies.
# Think: Kubernetes Deployment. We use a private IP (no public IP
# needed — only the app task talks to Redis).

resource "aws_ecs_service" "redis" {
  name            = "${var.project_name}-redis"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.redis.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public.id]
    security_groups  = [aws_security_group.redis.id]
    assign_public_ip = true # needed for image pull on public subnet
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# ── App task definition ───────────────────────────────────────────────
# The shortly app container. REDIS_HOST points at the Redis service
# via AWS Cloud Map (service discovery) — we use a simpler approach:
# we'll pass the Redis task's private IP via an environment variable.
# For this demo we use a fixed private IP approach via service connect,
# or more simply: run both containers in the same task.
#
# SIMPLIFICATION: for a clean learning demo we run app + Redis as
# two containers in the SAME task definition (they share a network
# namespace, so the app reaches Redis on localhost). Same simplification
# as ec2/ — co-location isn't production-shaped but demonstrates the
# Fargate pattern cleanly without service discovery complexity.

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "redis"
      image     = "redis:7.4-alpine"
      essential = false
      portMappings = [{
        containerPort = 6379
        protocol      = "tcp"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.redis.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "redis-sidecar"
        }
      }
    },
    {
      name      = "shortly"
      image     = var.app_image
      essential = true
      portMappings = [{
        containerPort = 5000
        protocol      = "tcp"
      }]
      environment = [
        { name = "REDIS_HOST", value = "localhost" },
        { name = "REDIS_PORT", value = "6379" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "shortly"
        }
      }
      dependsOn = [{
        containerName = "redis"
        condition     = "START"
      }]
    }
  ])

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# ── App ECS service ───────────────────────────────────────────────────

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public.id]
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}