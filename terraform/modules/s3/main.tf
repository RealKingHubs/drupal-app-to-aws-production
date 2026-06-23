# ============================================================
# S3 Module
# Free tier: 5GB storage, 20k GET, 2k PUT per month
# Used for Drupal file backups and static assets
# ============================================================

resource "aws_s3_bucket" "drupal_files" {
  bucket = "${var.project}-${var.environment}-files-${var.suffix}"
}

resource "aws_s3_bucket_versioning" "drupal_files" {
  bucket = aws_s3_bucket.drupal_files.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "drupal_files" {
  bucket = aws_s3_bucket.drupal_files.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "drupal_files" {
  bucket                  = aws_s3_bucket.drupal_files.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule to delete old versions after 7 days - keeps storage tiny
resource "aws_s3_bucket_lifecycle_configuration" "drupal_files" {
  bucket = aws_s3_bucket.drupal_files.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}