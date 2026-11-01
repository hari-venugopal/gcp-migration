variable "project_id" {
  description = "Your GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for Cloud Run, Cloud SQL and Artifact Registry."
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix for every resource name."
  type        = string
  default     = "amaze-lab"
}

variable "github_repo" {
  description = "GitHub repository allowed to deploy, as owner/name."
  type        = string
}

variable "api_min_instances" {
  description = "Minimum warm Cloud Run instances. 0 is cheapest; set 1+ to practise pre-scaling."
  type        = number
  default     = 0
}

variable "db_high_availability" {
  description = "true = REGIONAL Cloud SQL (zonal standby). Roughly doubles the database cost."
  type        = bool
  default     = false
}

variable "blocked_ip_ranges" {
  description = "Source ranges Cloud Armor denies. Add your own IP to test a block."
  type        = list(string)
  default     = ["192.0.2.0/24"]
}
