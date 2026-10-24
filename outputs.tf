output "site_bucket_name" {
  description = "S3 bucket that receives generated site files"
  value       = aws_s3_bucket.site.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution to invalidate after deployment"
  value       = aws_cloudfront_distribution.site.id
}

output "deploy_role_arn" {
  description = "GitHub Actions OIDC role for site deployment"
  value       = aws_iam_role.site_deploy.arn
}
