# Phase 2: Instance base role and profile
# The EC2 instance assumes this role, which has permission to assume the 3 container roles.

resource "aws_iam_role" "instance_base" {
  name = "${var.project_name}-instance-base-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-instance-base-role"
  }
}

resource "aws_iam_role_policy" "instance_assume_roles" {
  name = "${var.project_name}-assume-container-roles"
  role = aws_iam_role.instance_base.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          aws_iam_role.container_a_s3.arn,
          aws_iam_role.container_b_dynamodb.arn,
          aws_iam_role.container_c_kms.arn
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "demo" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.instance_base.name

  tags = {
    Name = "${var.project_name}-instance-profile"
  }
}
