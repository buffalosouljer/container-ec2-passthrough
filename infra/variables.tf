variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "container-roles-demo"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into the instance"
  type        = string
  default     = "0.0.0.0/0"
}
