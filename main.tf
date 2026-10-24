data "aws_caller_identity" "current" {}

variable "website_domain" {
  type    = string
  default = "2shell2furio.us"
}

data "aws_route53_zone" "website" {
  name = var.website_domain
}

locals {
  domain_name = var.website_domain
  bucket_name = var.website_domain

  tags = {
    Project = "2shell2furio.us"
    Domain  = "2shell2furio.us"
    Source  = "https://github.com/offbyone/2shell2furio-us"
  }
}

module "log_storage" {
  source = "github.com/offbyone/terraform-aws-s3-bucket-for-logs?ref=v0.7.3"

  bucket        = "logs.${local.domain_name}"
  s3_logs_path  = "s3-log-"
  cdn_logs_path = "cf-log-"
  readers       = [data.aws_caller_identity.current.account_id]
  tags          = local.tags
}

resource "aws_s3_bucket" "site" {
  bucket     = local.bucket_name
  depends_on = [module.log_storage]

  tags = local.tags
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_logging" "site" {
  bucket        = aws_s3_bucket.site.id
  target_bucket = module.log_storage.s3_logs_bucket
  target_prefix = module.log_storage.s3_logs_path
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = aws_s3_bucket.site.bucket_regional_domain_name
  description                       = "Private access to ${local.domain_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "site" {
  depends_on = [
    aws_acm_certificate_validation.site,
    aws_s3_bucket.site,
  ]

  comment             = "${local.domain_name} hosting"
  enabled             = true
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [local.domain_name]
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "S3-${local.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  logging_config {
    bucket          = module.log_storage.cdn_logs_bucket
    include_cookies = false
    prefix          = module.log_storage.cdn_logs_path
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3-${local.bucket_name}"
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.site.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = local.tags
}

data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid = "AllowCloudFrontRead"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json
}

resource "aws_acm_certificate" "site" {
  provider          = aws.useast1
  domain_name       = local.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, {
    Name = "2shell2furio-us"
  })
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.site.domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.website.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
}

resource "aws_acm_certificate_validation" "site" {
  provider                = aws.useast1
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

resource "aws_route53_record" "site" {
  zone_id = data.aws_route53_zone.website.zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_deployer_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:offbyone/2shell2furio-us:*"]
    }
  }
}

resource "aws_iam_role" "site_deploy" {
  name               = "2shell2furio-us-deployer"
  assume_role_policy = data.aws_iam_policy_document.github_deployer_trust.json
  tags               = local.tags
}

data "aws_iam_policy_document" "site_deploy" {
  statement {
    sid    = "ListSiteBucket"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
    ]

    resources = [aws_s3_bucket.site.arn]
  }

  statement {
    sid    = "ManageSiteObjects"
    effect = "Allow"

    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = ["${aws_s3_bucket.site.arn}/*"]
  }

  statement {
    sid       = "InvalidateSiteDistribution"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role_policy" "site_deploy" {
  name   = "deploy-site"
  role   = aws_iam_role.site_deploy.id
  policy = data.aws_iam_policy_document.site_deploy.json
}
