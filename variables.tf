# variables.tf — input parameters

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name, used in resource names and tags"
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
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port the app is exposed on (host side)"
  type        = number
  default     = 80
}

variable "app_image" {
  description = "Docker image for the shortly app"
  type        = string
  default     = "selase/shortly-app:latest"
}