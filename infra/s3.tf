resource "aws_s3_bucket" "demo" {
  bucket        = "${var.project_name}-bucket-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-bucket"
  }
}

resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
