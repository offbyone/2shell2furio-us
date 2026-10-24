# 2 Shell 2 Furio.us

A Pelican-generated timeline of real vulnerabilities with “Shell” names. The
site is a single static page hosted from a private S3 bucket through CloudFront.

## Setup

Prerequisites are managed by [mise](https://mise.jdx.dev/), with Python
packages managed by [uv](https://docs.astral.sh/uv/).

```sh
just setup
```

For local development:

```sh
just build
just serve
```

## Adding an exploit

Create one Markdown file in `content/articles/` with this metadata:

```markdown
Title: ExploitName
Date: YYYY-MM-DD
Slug: exploit-name
Cves: CVE-YYYY-NNNN
Summary: A compact plain-text summary.

One compact factual paragraph with [direct links to source material](https://example.com/).
```

Use the public disclosure date. Keep the body compact and link to primary or
reputable sources. Articles are authoring records only: Pelican renders them
directly into the homepage timeline and intentionally generates no standalone
article pages.

## Checks

```sh
just check
```

This performs a fatal production build, Ruff checks, Terraform formatting
checks, and Terraform validation. The final site should also be inspected in a
browser at wide and narrow viewport sizes.

## AWS infrastructure

Terraform expects these account prerequisites to exist:

- the `terraform.offby1.net` state bucket;
- a Route 53 hosted zone for `2shell2furio.us`;
- the GitHub Actions OIDC provider in IAM;
- a local AWS profile named `me`.

Provision explicitly:

```sh
just plan
just apply
terraform output
```

Copy `.env.example` to `.env`. Set `SITE_BUCKET` from the
`site_bucket_name` output and `CLOUDFRONT_DISTRIBUTION_ID` from the
corresponding Terraform output.

The GitHub repository also needs these Actions repository variables:

- `AWS_DEPLOY_ROLE_ARN` from `deploy_role_arn`;
- `CLOUDFRONT_DISTRIBUTION_ID` from `cloudfront_distribution_id`.

Infrastructure changes are applied locally, not by the content deployment
workflow.

## Publish

After Terraform has been applied and `.env` is configured:

```sh
just publish
```
