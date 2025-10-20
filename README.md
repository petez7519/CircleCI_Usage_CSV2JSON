# CircleCI Usage Data Pipeline

Automated pipeline to fetch CircleCI usage data, store it in S3, and convert it to hierarchical JSON format.

## Overview

This project provides a complete solution for:
- Fetching usage data from CircleCI Usage API (last 7 days)
- Uploading raw CSV data to S3
- Converting CSV to hierarchical JSON format (pipeline → workflow → jobs)
- Storing processed JSON in S3

## Architecture

```
CircleCI Pipeline
├── fetch-usage-data     → Calls Usage API, downloads CSV
├── upload-to-s3         → Uploads CSV to S3 bucket
└── convert-to-json      → Converts to JSON, uploads to S3
```

## Prerequisites

- CircleCI account with API access
- AWS account
- Terraform >= 1.0
- Python 3.11+

## Repository Structure

```
.
├── .circleci/
│   └── config.yml                  # CircleCI pipeline configuration
├── terraform/
│   ├── main.tf                     # Terraform infrastructure
│   └── terraform.tfvars            # Terraform variables (customize this)
├── convert_csv_to_json.py          # Python conversion script
└── README.md                       # This file
```

## Setup Instructions

### 1. AWS Infrastructure Setup

#### Configure Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
# AWS Configuration
aws_region = "us-east-1"

# S3 Bucket Name (must be globally unique)
bucket_name = "circleci-usage-data-your-org-name"

# CircleCI Organization
circleci_org_name = "your-org-name"

# Versioning
enable_versioning = true

# Lifecycle Management
lifecycle_days  = 90   # Move to Glacier after 90 days
expiration_days = 365  # Delete after 1 year
```

#### Deploy Infrastructure

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

#### Retrieve AWS Credentials

```bash
# Get Access Key ID
terraform output -raw access_key_id

# Get Secret Access Key
terraform output -raw secret_access_key

# Get bucket name
terraform output bucket_name
```

**⚠️ Important**: Store these credentials securely. You'll need them for CircleCI configuration.

### 2. CircleCI Configuration

#### Create Contexts

Create two contexts in CircleCI (Organization Settings → Contexts):

**Context: `circleci-usage-api`**
| `CIRCLECI_API_TOKEN` | CircleCI API token | `your-api-token` |
| `CIRCLECI_ORG_ID` | CircleCI organization ID | `your-org-uuid` |

**Context: `aws-credentials`**
| `AWS_ACCESS_KEY_ID` | AWS access key | Terraform output |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | Terraform output |
| `AWS_DEFAULT_REGION` | AWS region | `us-east-1` |
| `S3_BUCKET` | S3 bucket name | Terraform output |

#### How to Get CircleCI API Token

1. Go to [CircleCI User Settings](https://app.circleci.com/settings/user/tokens)
2. Click "Create New Token"
3. Name it "Usage API Access"
4. Copy the token and add to context

#### How to Get CircleCI Organization ID

```bash
curl -H "Circle-Token: YOUR_API_TOKEN" \
  https://circleci.com/api/v2/me/collaborations | jq '.[] | {name, id}'
```

### 3. Repository Setup

#### Add Python Script

Commit the `convert_csv_to_json.py` file to your repository root:

```bash
git add convert_csv_to_json.py
git commit -m "Add CSV to JSON conversion script"
git push
```

#### Add CircleCI Config

Commit the `.circleci/config.yml` file:

```bash
mkdir -p .circleci
git add .circleci/config.yml
git commit -m "Add CircleCI usage data pipeline"
git push
```

## Usage

### Manual Trigger

1. Go to your CircleCI project
2. Click "Trigger Pipeline"
3. Select branch (e.g., `main`)
4. Run the pipeline

### Scheduled Trigger (Optional)

Add to `.circleci/config.yml` under `workflows`:

```yaml
workflows:
  usage-data-pipeline:
    triggers:
      - schedule:
          cron: "0 2 * * 1"  # Every Monday at 2 AM UTC
          filters:
            branches:
              only:
                - main
    jobs:
      - fetch-usage-data:
          context: circleci-usage-api
      # ... rest of jobs
```

## Pipeline Jobs

### 1. fetch-usage-data

**Purpose**: Fetch usage data from CircleCI API

**Steps**:
1. Calculate date range (last 7 days)
2. Start CircleCI usage export job
3. Poll for completion (max 10 minutes)
4. Download CSV file

**Outputs**: 
- `usage-data-YYYY-MM-DD-to-YYYY-MM-DD.csv`

### 2. upload-to-s3

**Purpose**: Upload raw CSV to S3

**Steps**:
1. Attach workspace from previous job
2. Configure AWS CLI
3. Upload CSV to S3

**S3 Path**: 
- `s3://{bucket}/circleci-usage-data/usage-data-YYYY-MM-DD-to-YYYY-MM-DD.csv`

### 3. convert-to-json

**Purpose**: Convert CSV to hierarchical JSON

**Steps**:
1. Checkout repository (loads Python script)
2. Update script with dynamic filenames
3. Run Python conversion
4. Upload JSON to S3

**Output Structure**:
```json
[
  {
    "pipeline_id": "...",
    "pipeline_number": "...",
    "workflows": [
      {
        "workflow_id": "...",
        "workflow_name": "...",
        "jobs": [
          {
            "job_id": "...",
            "job_name": "...",
            "resource_class": "...",
            "credits": { ... }
          }
        ]
      }
    ]
  }
]
```

**S3 Path**: 
- `s3://{bucket}/circleci-usage-data/usage-data-YYYY-MM-DD-to-YYYY-MM-DD-hierarchical.json`

## Data Lifecycle

| Stage | Timeline | Storage Class | Cost |
|-------|----------|---------------|------|
| Active | 0-90 days | S3 Standard | $$$ |
| Archive | 90-365 days | S3 Glacier | $ |
| Deleted | 365+ days | - | Free |

## Monitoring

### Check Pipeline Status

```bash
# Via CircleCI UI
https://app.circleci.com/pipelines/{vcs}/{org}/{project}

# Via API
curl -H "Circle-Token: YOUR_TOKEN" \
  https://circleci.com/api/v2/project/{project-slug}/pipeline
```

### Verify S3 Uploads

```bash
# List recent uploads
aws s3 ls s3://YOUR_BUCKET/circleci-usage-data/ --recursive --human-readable

# Download a specific file
aws s3 cp s3://YOUR_BUCKET/circleci-usage-data/usage-data-2025-10-09-to-2025-10-16.json .
```

## Troubleshooting

### Pipeline Fails at `fetch-usage-data`

**Issue**: API token or org ID incorrect

**Solution**:
```bash
# Verify your token works
curl -H "Circle-Token: YOUR_TOKEN" \
  https://circleci.com/api/v2/me

# Verify org ID
curl -H "Circle-Token: YOUR_TOKEN" \
  https://circleci.com/api/v2/me/collaborations
```

### Pipeline Fails at `upload-to-s3`

**Issue**: AWS credentials incorrect or insufficient permissions

**Solution**:
```bash
# Test AWS credentials
aws sts get-caller-identity

# Test S3 access
aws s3 ls s3://YOUR_BUCKET/
```

### Export Job Times Out

**Issue**: Usage API export taking longer than 10 minutes

**Solution**: Increase timeout in config.yml:
```yaml
- run:
    name: Wait for export job to complete
    command: |
      MAX_ATTEMPTS=120  # Increase from 60 to 120 (20 minutes)
```

### No Data Returned

**Issue**: Date range has no activity

**Solution**: Adjust date range or check if org has recent pipeline runs

## Cost Estimation

### AWS Costs (Monthly)

Assuming ~100MB of usage data per week:

| Service | Usage | Cost |
|---------|-------|------|
| S3 Standard (0-90 days) | ~400MB | $0.01 |
| S3 Glacier (90-365 days) | ~1.2GB | $0.005 |
| Data Transfer | Negligible | $0.00 |
| **Total** | | **~$0.02/month** |

### CircleCI Costs

- API calls: Free (rate limited)
- Pipeline execution: Uses your plan's compute credits
- Estimated: ~50 credits per run (using medium resource class)

## Security Best Practices

✅ **Implemented**:
- S3 bucket encryption at rest
- No public access to S3 bucket
- Least-privilege IAM policy
- Credentials stored in CircleCI contexts
- Access keys not committed to git

⚠️ **Recommendations**:
- Rotate AWS access keys every 90 days
- Use AWS CloudTrail for audit logging
- Consider using OIDC instead of access keys for CircleCI → AWS authentication
- Enable S3 access logging if compliance required

## Maintenance

### Update Date Range

Edit `.circleci/config.yml`:
```python
# Change from 7 days to 30 days
end_date = datetime.now()
start_date = end_date - timedelta(days=30)  # Changed from 7
```

### Modify Lifecycle Policy

Edit `terraform/terraform.tfvars`:
```hcl
lifecycle_days  = 180  # Keep in Standard for 6 months
expiration_days = 730  # Keep for 2 years
```

Then apply:
```bash
cd terraform/
terraform apply
```

### Rotate AWS Credentials

```bash
cd terraform/

# Force recreation of access key
terraform taint aws_iam_access_key.circleci_s3_uploader
terraform apply

# Update CircleCI context with new credentials
terraform output -raw access_key_id
terraform output -raw secret_access_key
```

## Advanced Configuration

### Multi-Organization Support

To fetch data from multiple CircleCI organizations:

1. Create additional contexts for each org
2. Duplicate the workflow with different context names
3. Use different S3 prefixes for each org

### Custom Data Processing

Modify `convert_csv_to_json.py` to:
- Filter specific projects
- Calculate custom metrics
- Generate summary reports
- Export to different formats

### Notifications

Add Slack notifications to `.circleci/config.yml`:

```yaml
orbs:
  slack: circleci/slack@4.12.5

# Add to jobs:
- slack/notify:
    event: fail
    mentions: '@channel'
    template: basic_fail_1
```

## Support

### Documentation Links

- [CircleCI Usage API](https://circleci.com/docs/api/v2/#tag/Usage)
- [CircleCI Contexts](https://circleci.com/docs/contexts/)
- [AWS S3 Lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Questions?

For issues or questions:
1. Check CircleCI pipeline logs
2. Review CloudWatch logs (if enabled)
3. Check S3 bucket contents
4. Review Terraform state

## License

MIT License - Modify and use as needed for your organization.

---

**Last Updated**: October 2025  
**Version**: 1.0.0
