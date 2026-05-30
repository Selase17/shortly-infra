# main.tf — core resources for shortly-infra

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Region now comes from a variable instead of being hardcoded.
provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "demo" {
  # Bucket name built from a variable prefix + random suffix for global uniqueness.
  bucket = "${var.bucket_prefix}-${random_id.suffix.hex}"

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}