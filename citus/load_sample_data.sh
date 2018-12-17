#!/bin/bash

set -e

# load sample distributed table data for citus
# https://docs.citusdata.com/en/v8.0/use_cases/multi_tenant.html#let-s-make-an-app-ad-analytics

# download and import the sample schema from https://examples.citusdata.com/mt_ref_arch/schema.sql

curl -o sample_schema.sql https://examples.citusdata.com/mt_ref_arch/schema.sql

psql -U postgres -h localhost -d postgres < sample_schema.sql

# download and ingest datasets from the shell

for dataset in companies campaigns ads clicks impressions geo_ips; do
  curl -O https://examples.citusdata.com/mt_ref_arch/${dataset}.csv
done

cat <<EOF > load_sample_data.sql
\copy companies from 'companies.csv' with csv
\copy campaigns from 'campaigns.csv' with csv
\copy ads from 'ads.csv' with csv
\copy clicks from 'clicks.csv' with csv
\copy impressions from 'impressions.csv' with csv
EOF

psql -U postgres -h localhost -d postgres < load_sample_data.sql
