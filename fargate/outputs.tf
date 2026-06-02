
output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "app_service_name" {
  description = "ECS service name for the shortly app"
  value       = aws_ecs_service.app.name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "how_to_get_app_ip" {
  description = "Command to get the app task's public IP"
  value       = "aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.app.name} --query taskArns --output text | xargs aws ecs describe-tasks --cluster ${aws_ecs_cluster.main.name} --tasks | grep -i privateipv4"
}