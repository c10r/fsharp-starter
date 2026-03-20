variable "project_name" {
  description = "Human-readable project name. Used to derive kebab-case defaults such as bucket and repo names."
  type        = string

  validation {
    condition     = trimspace(var.project_name) != ""
    error_message = "Set project_name."
  }
}

variable "state_bucket_name" {
  description = "Optional override for the OpenTofu remote state bucket name. Defaults to iac-state-<project-name>."
  type        = string
  default     = ""
}

variable "state_bucket_storage_class" {
  description = "Storage class for the OpenTofu state bucket"
  type        = string
  default     = "STANDARD"
}

variable "state_bucket_force_destroy" {
  description = "Whether the foundation stack may destroy the state bucket"
  type        = bool
  default     = false
}

variable "github_repository_owner" {
  description = "GitHub organization or user that owns the repository allowed to deploy"
  type        = string
  default     = "wonderly"
}

variable "github_repository_name" {
  description = "Optional override for the GitHub repository name allowed to deploy. Defaults to internal-tools-<project-name>."
  type        = string
  default     = ""
}

variable "github_deploy_branch" {
  description = "Git branch or full ref allowed to deploy via GitHub Actions"
  type        = string
  default     = "main"
}

variable "github_workload_identity_pool_id" {
  description = "Workload Identity Pool ID used for GitHub Actions"
  type        = string
  default     = "github-actions"
}

variable "github_workload_identity_pool_display_name" {
  description = "Display name for the GitHub Actions Workload Identity Pool"
  type        = string
  default     = "GitHub Actions"
}

variable "github_workload_identity_provider_id" {
  description = "Optional override for the Workload Identity Provider ID used for GitHub Actions. Defaults to the kebab-case project name."
  type        = string
  default     = ""
}

variable "github_workload_identity_provider_display_name" {
  description = "Display name for the GitHub Actions Workload Identity Provider"
  type        = string
  default     = "FsharpStarter GitHub Provider"
}

variable "deploy_service_account_id" {
  description = "Optional override for the service account ID used by GitHub Actions deployments. Defaults to <project-name>-deploy."
  type        = string
  default     = ""
}
