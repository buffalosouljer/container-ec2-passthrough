# Phase 1: Legacy IAM users with static access keys
# These simulate the current state where containers use static credentials.
# In Phase 2, these are replaced by IAM roles + IMDS.

# --- Legacy S3 User (Container A) ---
resource "aws_iam_user" "legacy_s3" {
  name = "${var.project_name}-legacy-s3-user"

  tags = {
    Purpose = "Legacy static credentials for Container A - S3"
  }
}

resource "aws_iam_access_key" "legacy_s3" {
  user = aws_iam_user.legacy_s3.name
}

# --- Legacy DynamoDB User (Container B) ---
resource "aws_iam_user" "legacy_ddb" {
  name = "${var.project_name}-legacy-ddb-user"

  tags = {
    Purpose = "Legacy static credentials for Container B - DynamoDB"
  }
}

resource "aws_iam_access_key" "legacy_ddb" {
  user = aws_iam_user.legacy_ddb.name
}

# --- Legacy KMS User (Container C) ---
resource "aws_iam_user" "legacy_kms" {
  name = "${var.project_name}-legacy-kms-user"

  tags = {
    Purpose = "Legacy static credentials for Container C - KMS"
  }
}

resource "aws_iam_access_key" "legacy_kms" {
  user = aws_iam_user.legacy_kms.name
}
