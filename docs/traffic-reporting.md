# Traffic reporting

The site is served by CloudFront, which already provides basic traffic reports at
no additional charge. CloudFront standard access logging is also enabled in
[`main.tf`](../main.tf); compressed logs are written under
`s3://logs.2shell2furio.us/cf-log-/` for longer-term or custom analysis.

CloudFront and Athena report HTTP requests, not verified human visitors. Bots,
link-preview services, and requests for CSS or other assets can inflate totals.
The queries below reduce that noise but cannot remove it completely.

## Built-in CloudFront reports

Open the [CloudFront console](https://console.aws.amazon.com/cloudfront/v4/home),
choose the named report in the navigation pane, select this site's distribution
and date range, and choose **Update**.

| Question | Report | What to inspect |
| --- | --- | --- |
| How much attention is the site getting? | **Cache Statistics** | The **Total Requests** chart, preferably with daily granularity. |
| Where did requests come from? | **Top Referrers** | Referring domains. A dash means that no `Referer` header was sent. |
| Which pages or files are popular? | **Popular Objects** | Request counts by path. This one-page site will mostly show `/`, `/index.html`, and static assets. |
| Where are requests coming from geographically? | **Viewers** | The **Locations** report, grouped by country or U.S. state. |

Daily reports cover date ranges within the previous 60 days. Hourly Cache
Statistics and Locations data are available for ranges of up to 14 days within
that 60-day window. Dates and times are UTC.

These reports require no infrastructure change and do not depend on access
logging being enabled. They are the best first stop for a quick check.

## Query the access logs with Athena

Use Athena when the built-in reports are not specific enough or when data needs
to be analyzed after CloudFront's 60-day reporting window. Athena charges for
data scanned, with a 10 MB minimum per query; queries over this site's small,
compressed logs should normally cost a tiny fraction of a cent. S3 storage and
request charges also apply.

### One-time setup

1. Open the [Athena query editor](https://console.aws.amazon.com/athena/home#/query-editor)
   in **US West (Oregon) (`us-west-2`)**.
2. If Athena requests a query result location, set it to a separate prefix such
   as `s3://logs.2shell2furio.us/athena-results/`.
3. Run each of the following statements separately. The table location
   deliberately includes only the `cf-log-` prefix, so S3 access logs and Athena
   results are not parsed as CloudFront records.

```sql
CREATE DATABASE IF NOT EXISTS shell_site_traffic;

CREATE EXTERNAL TABLE IF NOT EXISTS shell_site_traffic.cloudfront_standard_logs (
  `date` DATE,
  time STRING,
  x_edge_location STRING,
  sc_bytes BIGINT,
  c_ip STRING,
  cs_method STRING,
  cs_host STRING,
  cs_uri_stem STRING,
  sc_status INT,
  cs_referrer STRING,
  cs_user_agent STRING,
  cs_uri_query STRING,
  cs_cookie STRING,
  x_edge_result_type STRING,
  x_edge_request_id STRING,
  x_host_header STRING,
  cs_protocol STRING,
  cs_bytes BIGINT,
  time_taken FLOAT,
  x_forwarded_for STRING,
  ssl_protocol STRING,
  ssl_cipher STRING,
  x_edge_response_result_type STRING,
  cs_protocol_version STRING,
  fle_status STRING,
  fle_encrypted_fields INT,
  c_port INT,
  time_to_first_byte FLOAT,
  x_edge_detailed_result_type STRING,
  sc_content_type STRING,
  sc_content_len BIGINT,
  sc_range_start BIGINT,
  sc_range_end BIGINT
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY '\t'
LOCATION 's3://logs.2shell2furio.us/cf-log-/'
TBLPROPERTIES ('skip.header.line.count' = '2');
```

CloudFront standard logs usually arrive within several hours, not immediately.
Restrict every query to a date range to reduce both cost and noise.

### Daily homepage requests

This counts successful homepage document requests while excluding common bots
and link-preview clients. It is a useful trend line, not a unique-visitor count.

```sql
SELECT
  "date",
  count(*) AS homepage_requests
FROM shell_site_traffic.cloudfront_standard_logs
WHERE "date" BETWEEN current_date - INTERVAL '30' DAY AND current_date
  AND cs_method = 'GET'
  AND sc_status BETWEEN 200 AND 399
  AND cs_uri_stem IN ('/', '/index.html')
  AND NOT regexp_like(
    lower(url_decode(cs_user_agent)),
    'bot|crawler|spider|slurp|preview|facebookexternalhit|headless|uptime|monitor'
  )
GROUP BY 1
ORDER BY 1;
```

### Rough daily visitor estimate

This counts distinct IP-address and user-agent combinations without displaying
the underlying values. Shared networks can merge different people, changing IPs
can split one person into several, and bots can still get through, so treat this
only as an estimate.

```sql
SELECT
  "date",
  count(DISTINCT concat(c_ip, '|', cs_user_agent)) AS estimated_visitors
FROM shell_site_traffic.cloudfront_standard_logs
WHERE "date" BETWEEN current_date - INTERVAL '30' DAY AND current_date
  AND cs_method = 'GET'
  AND sc_status BETWEEN 200 AND 399
  AND cs_uri_stem IN ('/', '/index.html')
  AND NOT regexp_like(
    lower(url_decode(cs_user_agent)),
    'bot|crawler|spider|slurp|preview|facebookexternalhit|headless|uptime|monitor'
  )
GROUP BY 1
ORDER BY 1;
```

### Top referring domains

This excludes direct visits, for which CloudFront records `-`, and groups the
remaining requests by referring hostname.

```sql
SELECT
  url_extract_host(url_decode(cs_referrer)) AS referring_domain,
  count(*) AS homepage_requests
FROM shell_site_traffic.cloudfront_standard_logs
WHERE "date" BETWEEN current_date - INTERVAL '30' DAY AND current_date
  AND cs_method = 'GET'
  AND sc_status BETWEEN 200 AND 399
  AND cs_uri_stem IN ('/', '/index.html')
  AND cs_referrer <> '-'
  AND NOT regexp_like(
    lower(url_decode(cs_user_agent)),
    'bot|crawler|spider|slurp|preview|facebookexternalhit|headless|uptime|monitor'
  )
GROUP BY 1
ORDER BY 2 DESC
LIMIT 50;
```

Browsers may omit or shorten the `Referer` header, so this report cannot account
for every source.

### Popular document paths

The current site has only one document, but this query will become useful if
more pages are added. It excludes common static asset extensions.

```sql
SELECT
  url_decode(cs_uri_stem) AS path,
  count(*) AS requests
FROM shell_site_traffic.cloudfront_standard_logs
WHERE "date" BETWEEN current_date - INTERVAL '30' DAY AND current_date
  AND cs_method = 'GET'
  AND sc_status BETWEEN 200 AND 399
  AND NOT regexp_like(
    lower(cs_uri_stem),
    '\.(css|js|png|jpe?g|gif|svg|webp|ico|woff2?|ttf|map)$'
  )
  AND NOT regexp_like(
    lower(url_decode(cs_user_agent)),
    'bot|crawler|spider|slurp|preview|facebookexternalhit|headless|uptime|monitor'
  )
GROUP BY 1
ORDER BY 2 DESC
LIMIT 50;
```

For geographic analysis, use CloudFront's **Viewers → Locations** report. The
legacy standard-log format currently configured for this distribution does not
include a country field, and deriving location from stored IP addresses adds
complexity and privacy concerns.

## Data handling

CloudFront logs contain client IP addresses and user-agent strings. Keep the log
bucket private, avoid exporting row-level data, and prefer aggregate query
results. If long-term raw logs are unnecessary, add an S3 lifecycle retention
policy rather than retaining them indefinitely.

## AWS references

- [View CloudFront reports in the console](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/reports.html)
- [View CloudFront viewers reports](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/viewers-reports.html)
- [Create an Athena table for CloudFront standard logs](https://docs.aws.amazon.com/athena/latest/ug/create-cloudfront-table-standard-logs.html)
- [Athena pricing](https://aws.amazon.com/athena/pricing/)
