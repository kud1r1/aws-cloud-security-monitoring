data "aws_caller_identity" "current" {}
# Terraform AWS provider
provider "aws" {
  region = "us-east-1"
}

# Random ID for unique S3 bucket name
resource "random_id" "bucket_id" {
  byte_length = 4
}

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "aws-cs-monitoring-logs-${random_id.bucket_id.hex}"
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs_versioning" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# CloudTrail for auditing AWS account activity
resource "aws_cloudtrail" "cloudtrail" {
  name                          = "aws-cs-monitoring-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
}

# CloudWatch log group to monitor events
resource "aws_cloudwatch_log_group" "cloudtrail_logs" {
  name              = "/aws/cloudtrail/logs"
  retention_in_days = 90
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "cs_monitoring_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Lambda function placeholder
resource "aws_lambda_function" "log_ingest" {
  filename         = "lambda/log_ingest.zip"  # Replace with real zip later
  function_name    = "cs_monitoring_log_ingest"
  handler          = "log_ingest.lambda_handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = filebase64sha256("lambda/log_ingest.zip")
}

resource "aws_s3_bucket_policy" "cloudtrail_logs_policy" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}
