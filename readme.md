
## Get Started

To get this repo, kindle clone this github repository

```bash
  git clone https://github.com/fishbones242/terraform-eks-repo.git
```
If you have not yet connected to your AWS Account. Enter aws configure

```bash
  aws configure
```
 
 Once configured, go to the terraform folder

```bash
  cd terraform-eks-repo
```

 inside the repo you have 3 TF files

- config.tf 
- eks.tf
- vpc.tf

Once configuration are modified. To deploy run this:
```bash
  terraform init
```

```bash
  terraform plan
```

```bash
  terraform apply
```

Once EKS has been created, to be able to connect inside the cluster. Execute:
```bash
aws eks update-kubeconfig --region region-code --name my-cluster
```

To test configuration

```bash
kubectl get svc
```
## TF Files
### config.tf
This is where you will going to define the necessary details for you EKS to be created

```terraform
locals {
  tags = {
    env          = "dev"
    cluster_name = local.cluster_name
  }
  cluster_name    = "eks-awscd-davao-dev-001" #Cluster Name
  region          = "ap-southeast-1" #What is your region?
  vpc_cidr        = "10.42.0.0/16" #Prefered cidr for vpc
  eks_version     = "1.30" #EKS Version
  node_group_ami  = "1.30.0-20240625" # What is your AMI for EC2 Node Groups
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

```

### vpc.tf
This module creates the following resources that the EKS needs:

- 1 VPC
- 3 Public subnets
- 3 Private subnets
- 1 Internet Gateway
- 1 NAT Gateway (single)
- Managed default network ACL
- Managed default route table
- Managed default security group
- DNS hostnames enabled for the VPC
```terraform
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.1"

  name = local.cluster_name
  cidr = local.vpc_cidr

  azs                   = local.azs
  public_subnets        = local.public_subnets
  private_subnets       = local.private_subnets
  public_subnet_suffix  = "SubnetPublic"
  private_subnet_suffix = "SubnetPrivate"

  enable_nat_gateway   = true
  create_igw           = true
  enable_dns_hostnames = true
  single_nat_gateway   = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.cluster_name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.cluster_name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.cluster_name}-default" }

  public_subnet_tags = merge(local.tags, {
    "kubernetes.io/role/elb" = "1"
  })
  private_subnet_tags = merge(local.tags, {
    "karpenter.sh/discovery"          = local.cluster_name
    "kubernetes.io/role/internal-elb" = "1"
  })

  tags = local.tags
}


locals {
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 3, k + 3)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 3, k)]
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
}

data "aws_availability_zones" "available" {
  state = "available"
}
```

### eks.tf
Main module that is what EKS creates
```terraform
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                             = local.cluster_name
  cluster_version                          = local.eks_version
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    vpc-cni = {
      before_compute = true
      most_recent    = true
      configuration_values = jsonencode({
        env = {
          ENABLE_POD_ENI                    = "true"
          ENABLE_PREFIX_DELEGATION          = "true"
          POD_SECURITY_GROUP_ENFORCING_MODE = "standard"
        }
        nodeAgent = {
          enablePolicyEventLogs = "true"
        }
        enableNetworkPolicy = "true"
      })
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_cluster_security_group = false
  create_node_security_group    = false

  eks_managed_node_groups = {
    default = {
      instance_types           = ["t3.micro"]
      force_update_version     = true
      release_version          = local.node_group_ami
      use_name_prefix          = false
      iam_role_name            = "${local.cluster_name}-ng-default"
      iam_role_use_name_prefix = false

      min_size     = 3
      max_size     = 6
      desired_size = 3

      update_config = {
        max_unavailable_percentage = 50
      }

      labels = {
        workshop-default = "yes"
      }
    }
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.cluster_name
  })
}
```