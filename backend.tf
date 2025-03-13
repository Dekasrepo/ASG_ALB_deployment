terraform {
  backend "s3" {
    bucket = "mystatefile12311"
    key = "terraform.state"
    region = "eu-west-3"
    encrypt = true
  }
}