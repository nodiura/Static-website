

provider "aws" {
  region = "us-east-1"
}
resource "aws_s3_bucket" "my_bucket" {
  bucket = "unique-bucket-name"  # Ensure this is unique globally
  acl    = "public-read"
  tags = {
    Name = "My Bucket"
  }
}
resource "aws_s3_bucket_website_configuration" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "error.html"
  }
  routing_rule {
    condition {
      key_prefix_equals = "docs/"
    }
    redirect {
      replace_key_prefix_with = "documents/"
      http_redirect_code      = "301"  # Optional: Specify the HTTP redirect code
    }
  }
}
# Step 2: Create an S3 bucket policy to allow public access
# Step 1: Define the primary S3 bucket for the website
resource "aws_s3_bucket" "website_bucket" {
  bucket = "my-tf-test-bucket"  # Ensure this bucket name is globally unique
}
# Step 2: Set the bucket policy for the website bucket
resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = aws_s3_bucket.website_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website_bucket.arn}/*"
      }
    ]
  })
}
# Step 3: Allow access from another AWS account
resource "aws_s3_bucket_policy" "allow_access_from_another_account" {
  bucket = aws_s3_bucket.website_bucket.id  # Use the same bucket
  policy = data.aws_iam_policy_document.allow_access_from_another_account.json
}
data "aws_iam_policy_document" "allow_access_from_another_account" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["123456789012"]  # Replace with the actual AWS Account ID
    }
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.website_bucket.arn,
      "${aws_s3_bucket.website_bucket.arn}/*",
    ]
  }
}
# Step 4: Define the lambda function and its source code in an S3 bucket
data "aws_s3_bucket_object" "lambda" {
  bucket = "ourcorp-lambda-functions"  # Ensure this bucket exists
  key    = "hello-world.zip"
}
resource "aws_lambda_function" "test_lambda" {
  s3_bucket         = data.aws_s3_bucket_object.lambda.bucket  # Corrected from id
  s3_key            = data.aws_s3_bucket_object.lambda.key
  s3_object_version = data.aws_s3_bucket_object.lambda.version_id
  function_name     = "lambda_function_name"
  role              = aws_iam_role.iam_for_lambda.arn  # Ensure this IAM role exists
  handler           = "exports.test"  # Ensure the handler is correct and defined
}
# Step 5: Create another S3 bucket for CloudFront
resource "aws_s3_bucket" "b" {
  bucket = "mybucket"  # Ensure this bucket name is globally unique
  tags = {
    Name = "My bucket"
  }
}
resource "aws_s3_bucket_acl" "b_acl" {
  bucket = aws_s3_bucket.b.id
  acl    = "private"
}
locals {
  s3_origin_id = "myS3Origin"
}
# Step 6: Define the CloudFront distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.b.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
    origin_id                = local.s3_origin_id
  }
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.html"
  logging_config {
    include_cookies = false
    bucket          = "mylogs.s3.amazonaws.com"  # Ensure this S3 bucket exists for logging
    prefix          = "myprefix"
  }
  aliases = ["mysite.example.com", "yoursite.example.com"]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id
    forwarded_values {
      query_string = false
      headers      = ["Origin"]
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }
  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    forwarded_values {
      query_string = false
      
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }
  price_class = "PriceClass_200"
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }
  tags = {
    Environment = "production"
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
# Step 7: Output the CloudFront domain name
output "cloudfront_domain" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name  # Corrected to match the resource name
}