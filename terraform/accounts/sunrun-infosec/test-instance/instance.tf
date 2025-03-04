data "aws_availability_zones" "available" {}

locals {
  name   = "ex-${basename(path.cwd)}"
  region = "us-west-2"

  vpc_cidr = data.terraform_remote_state.network.outputs.vpc_cidr_block
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Example    = local.name
    Owner      = "alex.balashov@sunrun.com"
    Department = "infosec"
    Managed_by = "Terraform"
  }
}

module "ec2" {
  source = "../../../../modules/aws/ec2-instance/"

  name = local.name

  subnet_id              = element(data.terraform_remote_state.network.outputs.private_subnets, 0)
  vpc_security_group_ids = [module.security_group_instance.security_group_id]

  create_iam_instance_profile = true
  iam_role_description        = "IAM role for EC2 instance"
  iam_role_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

# module "asg" {
#   source = "../../../../modules/aws/autoscaling/"
#
#   # Autoscaling group
#   name = "default-${local.name}"
#
#   vpc_zone_identifier = data.terraform_remote_state.network.outputs.private_subnets
#   min_size            = 0
#   max_size            = 1
#   desired_capacity    = 1
#
#   image_id      = data.aws_ami.amazon_linux.id
#   instance_type = "t3.micro"
#
#   tags = local.tags
# }


module "security_group_instance" {
  source  = "../../../../modules/aws/security-group/"

  name        = "${local.name}-ec2"
  description = "Security Group for EC2 Instance Egress"

  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = module.security_group_alb.security_group_id
    },
  ]
  egress_rules = ["all-all"]

  tags = local.tags
}

module "security_group_alb" {
  source  = "../../../../modules/aws/security-group/"

  name        = "${local.name}-alb"
  description = "Security Group for ALB HTTPS access only"

  vpc_id = data.terraform_remote_state.network.outputs.vpc_id


  ingress_with_cidr_blocks = [
    {
      rule        = "http-80-tcp"
      cidr_blocks = "46.109.66.158/32"
    },
  ]
  egress_rules  = ["all-all"]

  tags = local.tags
}

module "vpc_endpoints" {
  source  = "../../../../modules/aws/vpc-endpoint/"

  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

  endpoints = { for service in toset(["ssm", "ssmmessages", "ec2messages"]) :
    replace(service, ".", "_") =>
    {
      service             = service
      subnet_ids          = data.terraform_remote_state.network.outputs.private_subnets
      private_dns_enabled = true
      tags                = { Name = "${local.name}-${service}" }
    }
  }

  create_security_group      = true
  security_group_name_prefix = "${local.name}-vpc-endpoints-"
  security_group_description = "VPC endpoint security group"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from subnets"
      cidr_blocks = data.terraform_remote_state.network.outputs.private_subnets_cidr_blocks
    }
  }

  tags = local.tags
}


module "alb" {
  source  = "../../../../modules/aws/alb/"

  name = local.name

  vpc_id  = data.terraform_remote_state.network.outputs.vpc_id
  subnets = data.terraform_remote_state.network.outputs.public_subnets

  # For test only
  enable_deletion_protection = false

  # Security Group
  create_security_group = false
  security_groups = [module.security_group_alb.security_group_id]

  listeners = {
    ex_http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "ex_instance"
      }
    }
  }

  target_groups = {
    ex_instance = {
      backend_protocol                  = "HTTP"
      backend_port                      = 80
      target_type                       = "instance"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true
      target_id                         = module.ec2.id
    }
  }

  tags = local.tags
}