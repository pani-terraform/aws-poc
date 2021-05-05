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

resource "aws_subnet" "sn1" {
  vpc_id     = aws_vpc.prodvpc.id
  cidr_block = "10.1.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "web_private"
  }
}

resource "aws_route_table_association" "webapp_rt_asn1" {
  subnet_id      = aws_subnet.sn1.id
  route_table_id = aws_route_table.webapp_route_table.id
}

resource "aws_subnet" "sn2" {
  vpc_id     = aws_vpc.prodvpc.id
  cidr_block = "10.1.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "web_private2"
  }
}

resource "aws_route_table_association" "webapp_rt_asn2" {
  subnet_id      = aws_subnet.sn2.id
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

resource "aws_network_interface" "web1_nic" {
  subnet_id       = aws_subnet.sn1.id
  private_ips     = ["10.1.1.50"]
  security_groups = [aws_security_group.allow_sg.id]
}

#resource "aws_eip" "web_eip" {
#  vpc                       = true
#  network_interface         = aws_network_interface.web1_nic.id
#  associate_with_private_ip = "10.1.1.50"
#  depends_on                = [aws_internet_gateway.gw]
#}

resource "aws_launch_template" "lt_web" {
  name = "lt-web"

  image_id = "ami-06701ac70c2e4f546"
  instance_type = "t2.micro"
  key_name = "ec2-user-ubu"
  default_version = 2

  network_interfaces {
    device_index = 0
    network_interface_id = aws_network_interface.web1_nic.id
  }

  placement {
    availability_zone = "us-east-1a"
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "lt_web"
    }
  }

}

resource "aws_lb_target_group" "web_tg1" {
  name     = "tf-example-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.prodvpc.id
  
  health_check {
    path = "/index.html"
  }
}

resource "aws_lb" "alb_web" {
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_sg.id]
  subnets            = [aws_subnet.sn1.id, aws_subnet.sn2.id]

#enable_deletion_protection = true

  tags = {
    Environment = "production"
  }
}

resource "aws_autoscaling_group" "asg_web" {
  availability_zones = ["us-east-1a"]
  desired_capacity   = 1
  max_size           = 2
  min_size           = 1

  launch_template {
    id      = aws_launch_template.lt_web.id
    version = aws_launch_template.lt_web.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["tag"]
  }
}

# Create a new ALB Target Group attachment
resource "aws_autoscaling_attachment" "asg_attachment_bar" {
  autoscaling_group_name = aws_autoscaling_group.asg_web.id
  alb_target_group_arn   = aws_lb_target_group.web_tg1.arn
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.alb_web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg1.arn
  }
}

