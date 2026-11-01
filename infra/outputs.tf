output "app_url" {
  value = "http://${google_compute_global_address.lb.address}"
}

output "github_variables" {
  description = "Copy these into GitHub: Settings > Secrets and variables > Actions > Variables."
  value = {
    GCP_PROJECT  = var.project_id
    GCP_REGION   = var.region
    WIF_PROVIDER = google_iam_workload_identity_pool_provider.github.name
    DEPLOYER_SA  = google_service_account.deployer.email
    AR_REPO      = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
    API_SERVICE  = google_cloud_run_v2_service.api.name
    SPA_BUCKET   = google_storage_bucket.spa.name
    URL_MAP      = google_compute_url_map.main.name
  }
}
