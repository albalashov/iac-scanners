data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "sunrun-terraform-state"
    key    = "accounts/sunrun-infosec/infrastructure/terraform.tfstate"
    region = "us-west-2"
    profile = "sunrun-infosec"
  }
}

provider "aws" {
  region = local.region
  profile = "sunrun-infosec"
}

terraform {
  backend "s3" {
    bucket  = "sunrun-terraform-state"
    key     = "accounts/sunrun-infosec/test-instance/terraform.tfstate"
    region  = "us-west-2"
    profile = "sunrun-infosec"
  }
}