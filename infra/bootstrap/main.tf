# This config creates the S3 bucket + DynamoDB table that ALL OTHER
# Terraform configs (envs/dev, etc.) will use as their remote state backend.
#
# It deliberately uses LOCAL state itself -- you can't store your state
# backend's own definition in the backend it creates (chicken-and-egg).
# This is a one-time apply; the resulting local terraform.tfstate file for
# THIS config is small and safe to keep in .gitignore locally, but the
# S3 bucket name below is what matters -- write it down.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region for the state bucket/table"
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state. Bucket names are global across ALL AWS accounts, so pick something with your name/random suffix."
  type        = string
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  # Prevents `terraform destroy` (or an accidental console click) from
  # deleting this bucket while it still holds your state -- losing this
  # would mean losing track of every resource Terraform manages.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    # If state ever gets corrupted by a bad apply, you can roll back to a
    # previous version of the state file from the bucket's version history.
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.state_bucket_name}-locks"
  billing_mode = "PAY_PER_REQUEST" # no fixed cost -- pennies at this usage level
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}
