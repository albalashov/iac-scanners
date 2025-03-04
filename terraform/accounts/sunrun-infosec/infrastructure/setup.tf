provider "aws" {
  region = local.region
  profile = "sunrun-infosec"
}

terraform {
  backend "s3" {
    bucket  = "sunrun-terraform-state"
    key     = "accounts/sunrun-infosec/infrastructure/terraform.tfstate"
    region  = "us-west-2"
    profile = "sunrun-infosec"
  }
}