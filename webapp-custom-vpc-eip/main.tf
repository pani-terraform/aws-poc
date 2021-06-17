variable "region" {}
variable "devprofile" {}
variable "aws_ami" {}
variable "aws_instance_type" {}
variable "aws_ec2_tag" {}

# Configure the AWS Provider
provider "aws" {
  profile = var.devprofile
  region = var.region
  shared_credentials_file = "{{env `AWS_CRED`}}"
}

resource "aws_vpc" "prodvpc" {
  cidr_block = "10.1.0.0/16"

  tags = {
    Name = "production"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id     = aws_vpc.prodvpc.id

  tags = {
    Name = "gw"
  }
}

resource "aws_route_table" "webapp_route_table" {
  vpc_id = aws_vpc.prodvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "webapp_route_table"
  }
}

resource "aws_subnet" "web_private" {
  vpc_id     = aws_vpc.prodvpc.id
  cidr_block = "10.1.1.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "web_private"
  }
}

resource "aws_route_table_association" "webapp_rt_asn" {
  subnet_id      = aws_subnet.web_private.id
  route_table_id = aws_route_table.webapp_route_table.id
}

resource "aws_security_group" "allow_sg" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.prodvpc.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web_traffic"
  }
}

resource "aws_network_interface" "web_nic" {
  subnet_id       = aws_subnet.web_private.id
  private_ips     = ["10.1.1.50"]
  security_groups = [aws_security_group.allow_sg.id]
}

resource "aws_eip" "web_eip" {
  vpc                       = true
  network_interface         = aws_network_interface.web_nic.id
  associate_with_private_ip = "10.1.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

resource "aws_instance" "webapp" {
  ami           = var.aws_ami
  instance_type = var.aws_instance_type
  availability_zone = "us-west-2a"
  key_name = "ec2-user-w2"
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.web_nic.id
  }

  tags = {
    Name = var.aws_ec2_tag
  }
}