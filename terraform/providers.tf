terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  # Ці теги автоматично отримає кожен ресурс
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}