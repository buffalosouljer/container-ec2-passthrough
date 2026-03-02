# Phase 2: IAM roles for IMDS-based credential assumption
# Each container assumes its own scoped role via the EC2 instance profile.

# --- Container A: S3 Role ---
resource "aws_iam_role" "container_a_s3" {
  name = "${var.project_name}-container-a-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.instance_base.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-container-a-s3-role"
  }
}

resource "aws_iam_role_policy" "container_a_s3" {
  name = "${var.project_name}-container-a-s3-policy"
  role = aws_iam_role.container_a_s3.id

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

# --- Container B: DynamoDB Role ---
resource "aws_iam_role" "container_b_dynamodb" {
  name = "${var.project_name}-container-b-dynamodb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.instance_base.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-container-b-dynamodb-role"
  }
}

resource "aws_iam_role_policy" "container_b_dynamodb" {
  name = "${var.project_name}-container-b-dynamodb-policy"
  role = aws_iam_role.container_b_dynamodb.id

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

# --- Container C: KMS Role ---
resource "aws_iam_role" "container_c_kms" {
  name = "${var.project_name}-container-c-kms-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.instance_base.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-container-c-kms-role"
  }
}

resource "aws_iam_role_policy" "container_c_kms" {
  name = "${var.project_name}-container-c-kms-policy"
  role = aws_iam_role.container_c_kms.id

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
