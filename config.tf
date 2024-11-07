locals {
  tags = {
    env          = "dev"
    cluster_name = local.cluster_name
  }
  cluster_name    = "eks-awscd-davao-dev-001"
  region          = "ap-southeast-1"
  vpc_cidr        = "10.42.0.0/16"
  eks_version     = "1.30"
  node_group_ami  = "1.30.0-20240625"
}

provider "aws" {
  default_tags {
    tags = local.tags
  }
  region = local.region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.67.0"
    }
  }

  required_version = ">= 1.4.2"
}
