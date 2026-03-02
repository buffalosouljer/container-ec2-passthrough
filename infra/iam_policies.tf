# Scoped IAM policies for each legacy user

# --- S3 Policy (Container A) ---
resource "aws_iam_user_policy" "legacy_s3" {
  name = "${var.project_name}-s3-policy"
  user = aws_iam_user.legacy_s3.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.demo.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.demo.arn
      }
    ]
  })
}

# --- DynamoDB Policy (Container B) ---
resource "aws_iam_user_policy" "legacy_ddb" {
  name = "${var.project_name}-dynamodb-policy"
  user = aws_iam_user.legacy_ddb.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.demo.arn
      }
    ]
  })
}

# --- KMS Policy (Container C) ---
resource "aws_iam_user_policy" "legacy_kms" {
  name = "${var.project_name}-kms-policy"
  user = aws_iam_user.legacy_kms.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.demo.arn
      }
    ]
  })
}
