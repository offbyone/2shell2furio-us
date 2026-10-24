set dotenv-load

default: build

setup:
  mise install
  uv sync --all-groups
  tofu init

build settings="pelicanconf.py":
  uv run pelican --fatal=errors -s {{settings}} -o output content

serve:
  uv run inv livereload

generate: (build "publishconf.py")

check: generate
  uv run ruff check .
  tofu fmt -check
  tofu validate

upload:
  #!/usr/bin/env bash
  set -euo pipefail
  : "${SITE_BUCKET:?Set SITE_BUCKET in .env}"
  uv tool run --from awscli --with awscli-cwlogs aws s3 sync --delete output "s3://${SITE_BUCKET}"

invalidate:
  #!/usr/bin/env bash
  set -euo pipefail
  : "${CLOUDFRONT_DISTRIBUTION_ID:?Set CLOUDFRONT_DISTRIBUTION_ID in .env}"
  uv tool run --from awscli --with awscli-cwlogs aws cloudfront create-invalidation --distribution-id "${CLOUDFRONT_DISTRIBUTION_ID}" --paths "/*"

publish: generate upload invalidate

plan:
  tofu plan -out plan.just

apply:
  tofu apply plan.just
