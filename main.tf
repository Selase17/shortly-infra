# main.tf — VPC network foundation for shortly-infra

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

# Pull the list of availability zones in the region, so we don't
# hardcode AZ names (they differ per region). A "data source" reads
# existing info from AWS rather than creating anything.
data "aws_availability_zones" "available" {
  state = "available"
}

# ── VPC ─────────────────────────────────────────────────────────────
# The network itself. CIDR 10.0.0.0/16 gives ~65k private IPs to carve
# subnets from. enable_dns_* lets resources resolve each other by DNS.
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

# ── Internet Gateway ────────────────────────────────────────────────
# The door between the VPC and the public internet. Attaching it to the
# VPC is what makes internet access *possible* (routing still required).
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name      = "${var.project_name}-igw"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# ── Public subnet ───────────────────────────────────────────────────
# A slice of the VPC's IP range, placed in the first availability zone.
# map_public_ip_on_launch = true means instances here get a public IP.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name      = "${var.project_name}-public-subnet"
    Project   = var.project_name
    ManagedBy = "Terraform"
    Tier      = "public"
  }
}

# ── Private subnet ──────────────────────────────────────────────────
# Another slice, also in the first AZ, but NO public IPs and (below)
# no route to the internet gateway. For databases / internal services.
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name      = "${var.project_name}-private-subnet"
    Project   = var.project_name
    ManagedBy = "Terraform"
    Tier      = "private"
  }
}

# ── Public route table ──────────────────────────────────────────────
# A route table is a set of traffic rules. This one sends all traffic
# destined for outside the VPC (0.0.0.0/0) to the internet gateway.
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

# ── Associate the public route table with the public subnet ─────────
# A route table does nothing until associated with a subnet. This line
# is what actually makes the public subnet "public".
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}