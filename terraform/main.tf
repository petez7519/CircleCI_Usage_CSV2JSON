# Provider configuration
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket for CircleCI usage data"
  type        = string
}

variable "circleci_org_name" {
  description = "CircleCI organization name for tagging"
  type        = string
}

variable "enable_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "lifecycle_days" {
  description = "Number of days to retain usage data before archiving to Glacier"
  type        = number
  default     = 90
}

variable "expiration_days" {
  description = "Number of days to retain usage data before deletion"
  type        = number
  default     = 365
}

# S3 Bucket
resource "aws_s3_bucket" "circleci_usage_data" {
  bucket = var.bucket_name

  tags = {
    Name        = "CircleCI Usage Data"
    Environment = "Production"
    ManagedBy   = "Terraform"
    Purpose     = "CircleCI Usage API Data Storage"
    Org         = var.circleci_org_name
  }
}

# Bucket Versioning
resource "aws_s3_bucket_versioning" "circleci_usage_data" {
  bucket = aws_s3_bucket.circleci_usage_data.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "circleci_usage_data" {
  bucket = aws_s3_bucket.circleci_usage_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block Public Access
resource "aws_s3_bucket_public_access_block" "circleci_usage_data" {
  bucket = aws_s3_bucket.circleci_usage_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle Policy
resource "aws_s3_bucket_lifecycle_configuration" "circleci_usage_data" {
  bucket = aws_s3_bucket.circleci_usage_data.id

  rule {
    id     = "archive-old-usage-data"
    status = "Enabled"

    filter {
      prefix = "circleci-usage-data/"
    }

    transition {
      days          = var.lifecycle_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# IAM User for CircleCI
resource "aws_iam_user" "circleci_s3_uploader" {
  name = "circleci-usage-data-uploader"
  path = "/service-accounts/"

  tags = {
    Name      = "CircleCI Usage Data Uploader"
    ManagedBy = "Terraform"
    Purpose   = "Upload usage data from CircleCI to S3"
  }
}

# IAM Policy for S3 Access
resource "aws_iam_policy" "circleci_s3_upload_policy" {
  name        = "circleci-usage-data-s3-upload"
  description = "Policy for CircleCI to upload usage data to S3"
  path        = "/service-accounts/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.circleci_usage_data.arn
      },
      {
        Sid    = "PutObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.circleci_usage_data.arn}/circleci-usage-data/*"
      }
    ]
  })
}

# Attach Policy to User
resource "aws_iam_user_policy_attachment" "circleci_s3_upload_attach" {
  user       = aws_iam_user.circleci_s3_uploader.name
  policy_arn = aws_iam_policy.circleci_s3_upload_policy.arn
}

# Create Access Key (use this carefully - consider using OIDC instead)
resource "aws_iam_access_key" "circleci_s3_uploader" {
  user = aws_iam_user.circleci_s3_uploader.name
}

# Outputs
output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.circleci_usage_data.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.circleci_usage_data.arn
}

output "bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.circleci_usage_data.region
}

output "iam_user_name" {
  description = "IAM user name for CircleCI"
  value       = aws_iam_user.circleci_s3_uploader.name
}

output "iam_user_arn" {
  description = "IAM user ARN"
  value       = aws_iam_user.circleci_s3_uploader.arn
}

output "access_key_id" {
  description = "Access key ID for CircleCI (sensitive)"
  value       = aws_iam_access_key.circleci_s3_uploader.id
  sensitive   = true
}

output "secret_access_key" {
  description = "Secret access key for CircleCI (sensitive)"
  value       = aws_iam_access_key.circleci_s3_uploader.secret
  sensitive   = true
}

output "usage_instructions" {
  description = "Instructions for using the credentials"
  value       = <<-EOT
    
    To retrieve the sensitive credentials, run:
    terraform output -raw access_key_id
    terraform output -raw secret_access_key
    
    Add these to your CircleCI context 'aws-credentials':
    - AWS_ACCESS_KEY_ID: (from access_key_id output)
    - AWS_SECRET_ACCESS_KEY: (from secret_access_key output)
    - AWS_DEFAULT_REGION: ${var.aws_region}
    - S3_BUCKET: ${var.bucket_name}
  EOT
}
