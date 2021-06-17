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
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = "production"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id     = aws_vpc.prodvpc.id

  tags = {
    Name = "igw"
  }
}

resource "aws_route_table" "rt1" {
  vpc_id = aws_vpc.prodvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "route_table"
  }
}

resource "aws_subnet" "sn_db" {
  vpc_id     = aws_vpc.prodvpc.id
  cidr_block = "10.1.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Private"
  }
}

resource "aws_subnet" "sn_db1" {
  vpc_id     = aws_vpc.prodvpc.id
  cidr_block = "10.1.3.0/24"
  availability_zone = "us-east-1c"

  tags = {
    Name = "Private"
  }
}

resource "aws_subnet" "sn_app" {
  vpc_id     = aws_vpc.prodvpc.id
  cidr_block = "10.1.2.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public"
  }
}

resource "aws_route_table_association" "db_rt" {
  subnet_id      = aws_subnet.sn_db.id
  route_table_id = aws_route_table.rt1.id
}

resource "aws_route_table_association" "db1_rt" {
  subnet_id      = aws_subnet.sn_db1.id
  route_table_id = aws_route_table.rt1.id
}

resource "aws_route_table_association" "app_rt" {
  subnet_id      = aws_subnet.sn_app.id
  route_table_id = aws_route_table.rt1.id
}

resource "aws_security_group" "sg_app" {
  name        = "sg_app"
  description = "Allow ssh inbound traffic"
  vpc_id      = aws_vpc.prodvpc.id

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
    Name = "allow_ssh_traffic"
  }
}

resource "aws_security_group" "sg_db" {
  name        = "sg_db"
  description = "Allow MySQl inbound traffic"
  vpc_id      = aws_vpc.prodvpc.id

  ingress {
    description      = "MySQL"
    from_port        = 3306
    to_port          = 3306
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
    Name = "allow_mysql_traffic"
  }
}

resource "aws_network_interface" "app1_nic" {
  subnet_id       = aws_subnet.sn_app.id
  private_ips     = ["10.1.2.50"]
  security_groups = [aws_security_group.sg_app.id]
}

resource "aws_launch_template" "lt_app" {
  name = "lt_app"

  image_id = "ami-0def94988b0664157"
  instance_type = "t2.micro"
  key_name = "ec2-user-ubu"

  network_interfaces {
    device_index = 0
    network_interface_id = aws_network_interface.app1_nic.id
  }

  placement {
    availability_zone = "us-east-1a"
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "lt_app"
    }
  }

}

resource "aws_autoscaling_group" "asg_app" {
  availability_zones = ["us-east-1a", "us-east-1b"]
  desired_capacity   = 1
  max_size           = 1
  min_size           = 1

  launch_template {
    id      = aws_launch_template.lt_app.id
    version = "$Latest"
  }
}

resource "aws_db_subnet_group" "db_sng" {
  name       = "main"
  subnet_ids = [aws_subnet.sn_db.id, aws_subnet.sn_db1.id]

  tags = {
    Name = "My DB subnet group"
  }
}

resource "aws_db_instance" "mysql_dev" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  name                 = "mydb"
  username             = "admin"
  password             = "TopSecret1"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.db_sng.id
  vpc_security_group_ids = [aws_security_group.sg_db.id]
}

resource "aws_route53_zone" "pani" {
  name = "pani.com"

  vpc {
    vpc_id = aws_vpc.prodvpc.id
  }
}

resource "aws_route53_record" "mysql_db_dev" {
  zone_id = aws_route53_zone.pani.zone_id
  name    = "mysql_db_dev"
  type    = "CNAME"
  ttl     = "5"

  weighted_routing_policy {
    weight = 100
  }

  set_identifier = "dev"
  records        = [aws_db_instance.mysql_dev.address]
}