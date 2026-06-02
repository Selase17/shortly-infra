
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name used in resource names and tags"
  type        = string
  default     = "shortly-infra"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.3.0/24"
}

variable "app_port" {
  description = "Port the app container exposes on the host"
  type        = number
  default     = 5000
}

variable "app_image" {
  description = "Docker image for the shortly app"
  type        = string
  default     = "selase/shortly-app:latest"
}