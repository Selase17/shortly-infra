
# variables.tf — input parameters for the configuration

variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name, applied as a tag to all resources"
  type        = string
  default     = "shortly-infra"
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name (a random suffix is appended for global uniqueness)"
  type        = string
  default     = "shortly-infra-demo"
}