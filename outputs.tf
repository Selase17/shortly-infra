# outputs.tf — values reported after apply

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Public IP of the instance"
  value       = aws_instance.app.public_ip
}

output "app_url" {
  description = "URL to reach the shortly app"
  value       = "http://${aws_instance.app.public_ip}:${var.app_port == 80 ? "" : var.app_port}"
}

output "healthz_url" {
  description = "Health check URL"
  value       = "http://${aws_instance.app.public_ip}${var.app_port == 80 ? "" : ":${var.app_port}"}/healthz"
}