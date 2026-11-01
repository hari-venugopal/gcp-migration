# ---------- Cloud Armor ----------
# Edge policy for the bucket (static content).
resource "google_compute_security_policy" "edge" {
  name = "${var.name_prefix}-edge"
  type = "CLOUD_ARMOR_EDGE"

  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = var.blocked_ip_ranges
      }
    }
    description = "Blocked ranges"
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow"
  }

  depends_on = [google_project_service.apis]
}

# Backend policy for the API: IP blocks plus an OWASP SQL injection rule.
resource "google_compute_security_policy" "api" {
  name = "${var.name_prefix}-api"

  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = var.blocked_ip_ranges
      }
    }
    description = "Blocked ranges"
  }

  rule {
    action   = "deny(403)"
    priority = 2000
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "OWASP SQL injection"
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow"
  }

  depends_on = [google_project_service.apis]
}

# ---------- Backends ----------
resource "google_compute_backend_bucket" "spa" {
  name                 = "${var.name_prefix}-spa"
  bucket_name          = google_storage_bucket.spa.name
  enable_cdn           = true
  edge_security_policy = google_compute_security_policy.edge.id

  cdn_policy {
    cache_mode = "USE_ORIGIN_HEADERS" # hashed bundles: immutable; index.html: no-cache
  }
}

resource "google_compute_region_network_endpoint_group" "api" {
  name                  = "${var.name_prefix}-api-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = google_cloud_run_v2_service.api.name
  }
}

resource "google_compute_backend_service" "api" {
  name                  = "${var.name_prefix}-api"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.api.id

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# ---------- Routing: /api/* to Cloud Run, everything else to the bucket ----------
resource "google_compute_url_map" "main" {
  name            = "${var.name_prefix}-urlmap"
  default_service = google_compute_backend_bucket.spa.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "main"
  }

  path_matcher {
    name            = "main"
    default_service = google_compute_backend_bucket.spa.id

    path_rule {
      paths   = ["/api", "/api/*"]
      service = google_compute_backend_service.api.id
    }
  }
}

resource "google_compute_global_address" "lb" {
  name       = "${var.name_prefix}-ip"
  depends_on = [google_project_service.apis]
}

# HTTP keeps the lab free of DNS and certificates. See README for adding HTTPS.
resource "google_compute_target_http_proxy" "main" {
  name    = "${var.name_prefix}-http"
  url_map = google_compute_url_map.main.id
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.name_prefix}-http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.address
  port_range            = "80"
  target                = google_compute_target_http_proxy.main.id
}
