# AWS Configuration
aws_region = "us-east-1"

# S3 Bucket Name (must be globally unique)
bucket_name = "circleci-usage-data-petez7519"

# CircleCI Organization
circleci_org_name = "petez7519"

# Versioning
enable_versioning = true

# Lifecycle Management
lifecycle_days  = 90   # Move to Glacier after 90 days
expiration_days = 365  # Delete after 1 year
