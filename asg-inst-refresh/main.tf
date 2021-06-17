variable "region" {}
variable "devprofile" {}

# Configure the AWS Provider
provider "aws" {
  profile = var.devprofile
  region = var.region
  shared_credentials_file = "{{env `AWS_CRED`}}"
}

data "aws_ami" "test" {
  owners           = ["670461732659"]

  filter {
    name   = "name"
    values = ["*"]
  }

}
