output "workspace_id" {
  description = "ID of the existing NHS Fabric Dev workspace"
  value       = data.fabric_workspace.nhs_dev.id
}

output "workspace_name" {
  description = "Name of the Fabric workspace"
  value       = var.workspace_name
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}