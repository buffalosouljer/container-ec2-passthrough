resource "aws_instance" "demo" {
  ami                    = "ami-09722669c73b517f6" # Fedora 41 Cloud Base
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.demo.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"    # IMDSv2 only
    http_put_response_hop_limit = 2             # Allow containers to reach IMDS
  }

  user_data_replace_on_change = true
  user_data_base64 = base64gzip(templatefile("${path.module}/user_data.sh.tftpl", {
    region               = var.region
    s3_bucket            = aws_s3_bucket.demo.id
    dynamodb_table       = aws_dynamodb_table.demo.name
    kms_key_id           = aws_kms_key.demo.key_id
    s3_access_key        = aws_iam_access_key.legacy_s3.id
    s3_secret_key        = aws_iam_access_key.legacy_s3.secret
    ddb_access_key       = aws_iam_access_key.legacy_ddb.id
    ddb_secret_key       = aws_iam_access_key.legacy_ddb.secret
    kms_access_key       = aws_iam_access_key.legacy_kms.id
    kms_secret_key       = aws_iam_access_key.legacy_kms.secret
    container_a_role_arn = aws_iam_role.container_a_s3.arn
    container_b_role_arn = aws_iam_role.container_b_dynamodb.arn
    container_c_role_arn = aws_iam_role.container_c_kms.arn
  }))

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-instance"
  }
}
