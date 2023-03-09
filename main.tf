data "aws_region" "current" {}

# Retrieve my public IP address
data "http" "my_public_ip" {
  url = "http://ipv4.icanhazip.com"
}

# CSR AMI
data "aws_ami" "this" {
  owners      = ["aws-marketplace"]
  most_recent = true

  filter {
    name   = "name"
    values = var.csr_ami == "BYOL" ? [var.csr_ami_byol_ami] : [var.csr_ami_sec_ami]
  }
}

# Running config template
data "template_file" "running_config" {
  template = file("${path.module}/running-config.tpl")

  vars = {
    admin_password = var.admin_password
    hostname       = var.csr_hostname
  }
}

# Create a Security Group for Cisco CSR Gi1
resource "aws_security_group" "gi1_sg" {
  vpc_id = var.vpc_id
  name   = "CSR GigabitEthernet1 Security Group for ${var.csr_hostname}"

  dynamic "ingress" {
    for_each = local.ingress_ports

    content {
      description = ingress.key
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.egress_cidr_blocks
  }

  tags = {
    Name = "csr-gi1-sg"
  }

  lifecycle {
    ignore_changes = [ingress, egress]
  }
}

# Create a Security Group for Cisco CSR Gi2
resource "aws_security_group" "gi2_sg" {
  vpc_id = var.vpc_id
  name   = "CSR GigabitEthernet2 Security Group for ${var.csr_hostname}"

  dynamic "ingress" {
    for_each = local.ingress_ports

    content {
      description = ingress.key
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.egress_cidr_blocks
  }

  tags = {
    Name = "csr-gi2-sg"
  }

  lifecycle {
    ignore_changes = [ingress, egress]
  }
}

# Create eni for CSR Gi1
resource "aws_network_interface" "csr_gi1" {
  description       = "CSR GigabitEthernet1"
  subnet_id         = var.gi1_subnet_id
  security_groups   = [aws_security_group.gi1_sg.id]
  source_dest_check = false

  tags = {
    Name = "csr-gi1-eni"
  }
}

# Create eni for CSR Gi2
resource "aws_network_interface" "csr_gi2" {
  description       = "CSR GigabitEthernet2"
  subnet_id         = var.gi2_subnet_id
  security_groups   = [aws_security_group.gi2_sg.id]
  source_dest_check = false

  tags = {
    Name = "csr-gi2-eni"
  }
}

# Allocate EIP for CSR Gi1
resource "aws_eip" "this" {
  vpc               = true
  network_interface = aws_network_interface.csr_gi1.id

  tags = {
    "Name" = "CSR-Gi1-EIP@${var.csr_hostname}"
  }
}

# Create CSR EC2 instance
resource "aws_instance" "this" {
  ami           = data.aws_ami.this.id
  instance_type = var.instance_type
  key_name      = var.key_name

  network_interface {
    network_interface_id = aws_network_interface.csr_gi1.id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.csr_gi2.id
    device_index         = 1
  }

  user_data = local.csr_bootstrap

  tags = {
    Name = var.csr_hostname
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
