# Static hosting for the SPA. Hashed bundles are immutable and never deleted;
# releases/<sha>/index.html holds every version; /index.html is the "active" pointer.
resource "google_storage_bucket" "spa" {
  name                        = "${var.project_id}-${var.name_prefix}-spa"
  location                    = "US" # multi-region, like the real design
  uniform_bucket_level_access = true
  force_destroy               = true # lab only

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html" # SPA deep links
  }

  versioning {
    enabled = true
  }
}

# Lab simplification: public read. The real design kept the live bucket private
# inside a VPC Service Controls perimeter and only Akamai could reach the origin.
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.spa.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
