resource "google_artifact_registry_repository" "images" {
  repository_id = var.name_prefix
  location      = var.region
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

# The API's own identity: no keys, least privilege.
resource "google_service_account" "api" {
  account_id   = "${var.name_prefix}-api"
  display_name = "Items API runtime"
}

resource "google_secret_manager_secret_iam_member" "api_reads_db_password" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

# Terraform creates the service and its first revision (a placeholder image).
# After that the pipeline owns the image and traffic, so Terraform ignores them.
resource "google_cloud_run_v2_service" "api" {
  name                = "${var.name_prefix}-api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" # only reachable through the load balancer
  deletion_protection = false

  template {
    service_account                  = google_service_account.api.email
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = var.api_min_instances
      max_instance_count = 5
    }

    vpc_access {
      network_interfaces {
        network    = google_compute_network.vpc.id
        subnetwork = google_compute_subnetwork.run.id
      }
      egress = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      resources {
        limits            = { cpu = "1", memory = "512Mi" }
        startup_cpu_boost = true
      }

      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.pg.private_ip_address
      }
      env {
        name  = "DB_NAME"
        value = google_sql_database.items.name
      }
      env {
        name  = "DB_USER"
        value = google_sql_user.api.name
      }
      env {
        name  = "DB_SSL_MODE"
        value = "Require"
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      client,
      client_version,
      traffic,
      template[0].revision,
      template[0].labels,
      template[0].containers[0].image,
      template[0].containers[0].env,
    ]
  }

  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret_iam_member.api_reads_db_password,
    google_secret_manager_secret_version.db_password,
  ]
}

# Ingress is restricted to the load balancer, so public invoke is safe here.
resource "google_cloud_run_v2_service_iam_member" "lb_invoke" {
  name     = google_cloud_run_v2_service.api.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}
