resource "aws_kms_key" "demo" {
  description             = "KMS key for ${var.project_name} container C"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowLegacyKmsUser"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.legacy_kms.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowContainerKmsRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.container_c_kms.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-key"
  }
}

resource "aws_kms_alias" "demo" {
  name          = "alias/${var.project_name}-key"
  target_key_id = aws_kms_key.demo.key_id
}
