resource "aws_security_group" "instance" {
  name        = "${var.project_name}-sg"
  description = "Security group for the demo EC2 instance"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.instance.id
  description       = "SSH access"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowed_ssh_cidr
}

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.instance.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
