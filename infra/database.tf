resource "google_sql_database_instance" "pg" {
  name                = "${var.name_prefix}-pg"
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = false # lab only

  settings {
    edition           = "ENTERPRISE" # the real design uses ENTERPRISE_PLUS
    tier              = "db-f1-micro"
    availability_type = var.db_high_availability ? "REGIONAL" : "ZONAL"
    disk_size         = 10

    ip_configuration {
      ipv4_enabled    = false # no public IP
      private_network = google_compute_network.vpc.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }
  }

  depends_on = [google_service_networking_connection.psa]
}

resource "google_sql_database" "items" {
  name     = "items"
  instance = google_sql_database_instance.pg.name
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "google_sql_user" "api" {
  name     = "items_api"
  instance = google_sql_database_instance.pg.name
  password = random_password.db.result
}

# The password lives only in Secret Manager; Cloud Run injects it at startup.
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.name_prefix}-db-password"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}
