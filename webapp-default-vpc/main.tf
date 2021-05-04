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

resource "aws_instance" "ocp_bastion" {
  ami           = var.aws_ami
  instance_type = var.aws_instance_type

  tags = {
    Name = var.aws_ec2_tag
  }
}