output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.demo.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.demo.id
}

# Legacy access keys (Phase 1)
output "s3_access_key_id" {
  description = "Access key ID for legacy S3 user"
  value       = aws_iam_access_key.legacy_s3.id
  sensitive   = true
}

output "s3_secret_access_key" {
  description = "Secret access key for legacy S3 user"
  value       = aws_iam_access_key.legacy_s3.secret
  sensitive   = true
}

output "ddb_access_key_id" {
  description = "Access key ID for legacy DynamoDB user"
  value       = aws_iam_access_key.legacy_ddb.id
  sensitive   = true
}

output "ddb_secret_access_key" {
  description = "Secret access key for legacy DynamoDB user"
  value       = aws_iam_access_key.legacy_ddb.secret
  sensitive   = true
}

output "kms_access_key_id" {
  description = "Access key ID for legacy KMS user"
  value       = aws_iam_access_key.legacy_kms.id
  sensitive   = true
}

output "kms_secret_access_key" {
  description = "Secret access key for legacy KMS user"
  value       = aws_iam_access_key.legacy_kms.secret
  sensitive   = true
}

# Resource ARNs
output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.demo.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.demo.id
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.demo.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.demo.name
}

output "kms_key_arn" {
  description = "ARN of the KMS key"
  value       = aws_kms_key.demo.arn
}

output "kms_key_id" {
  description = "ID of the KMS key"
  value       = aws_kms_key.demo.key_id
}

# Phase 2: Role ARNs
output "instance_base_role_arn" {
  description = "ARN of the instance base role"
  value       = aws_iam_role.instance_base.arn
}

output "container_a_role_arn" {
  description = "ARN of the Container A S3 role"
  value       = aws_iam_role.container_a_s3.arn
}

output "container_b_role_arn" {
  description = "ARN of the Container B DynamoDB role"
  value       = aws_iam_role.container_b_dynamodb.arn
}

output "container_c_role_arn" {
  description = "ARN of the Container C KMS role"
  value       = aws_iam_role.container_c_kms.arn
}
