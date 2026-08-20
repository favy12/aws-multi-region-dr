terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}

provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      ManagedBy  = "terraform"
      Repository = "aws-multi-region-dr"
      DRRole     = "primary"
    }
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      ManagedBy  = "terraform"
      Repository = "aws-multi-region-dr"
      DRRole     = "standby"
    }
  }
}

# Route53 health check metrics are only published in us-east-1, so alarms on
# them have to be created there no matter where the workload runs.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      ManagedBy  = "terraform"
      Repository = "aws-multi-region-dr"
    }
  }
}
