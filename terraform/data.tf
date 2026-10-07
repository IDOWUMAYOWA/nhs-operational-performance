data "fabric_workspace" "nhs_dev" {
  display_name                   = var.workspace_name
  skip_capacity_state_validation = true
}