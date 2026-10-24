terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.67.0"
    }
  }

  required_version = ">= 1.7"

  backend "s3" {
    bucket = "terraform.offby1.net"
    key    = "website/2shell2furio-us/state.tfstate"
    region = "us-west-2"
  }
}

provider "aws" {
  profile = "me"
  region  = "us-west-2"
}

provider "aws" {
  alias   = "useast1"
  profile = "me"
  region  = "us-east-1"
}
