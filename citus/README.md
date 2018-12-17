# Citus DB

Hasura on Citus. This uses Citus 8.0 and Hasura v1.0.0-alpha31.

## Setup

### Pre-requisites

1. docker-compose
2. psql

### Run citus and hasura 

1. Download the `docker-compose.yaml` file

2. Run `docker-compose -p citus up -d`

This will start a Citus cluster with one worker, and a Hasura GraphQL Engine pointing to the citus instance.

### Import sample data from Citus multi-tenant example app dataset

1. Download the `load_sample_data.sh` and run it to load sample data into the citus instance.

```shell
$ chmod +x load_sample_data.sh && ./load_sample_data.sh
```

### Add hasura metadata

1. Open the console
2. Track all the tables
3. Create relationships mentioned below, or use the `metadata.json` file to import the relationships. 


## The schema

All the tables are distributed tables. The distribution column is `company_id`
(for `companies` table it is the `id` column).

Following are the tables and foreign key references among them:

1. `companies`
2. `campaigns` : `campaigns.company_id` -> `companies.id`
3. `ads` : `ads.campaign_id` -> `campaigns.id` , `ads.company_id` -> `companies.id` 
4. `clicks` :  `clicks.ad_id` -> `ads.id` , `clicks.company_id` -> `companies.id` 
5. `impressions` : `impressions.ad_id` -> `ads.id` , `impressions.company_id` -> `companies.id` 

## Hasura relationships

1. `campaigns` has an object relationship to `companies` and array relationships to `ads`
2. `ads` has an object relationship to `campaigns` and array relationships to `clicks` and `impressions`
3. `clicks` has an object relationship to `ads`
4. `impressions` has an object relationship to `ads`
<!-- 5. `ads`, `clicks`, `impressions` tables also has an object relationship to `companies` -->


## Querying the existing data

**NOTE**: `company_id` is required at top-level for all queries, because its the distribution column in citus.

```graphql
query AllCampaignsOfCompany ($companyId: bigint!) {
  campaigns(where: {company_id: {_eq: $companyId}}) {
    name
    company {
      name
    }
    cost_model
    monthly_budget
    state
  }
}

query AllCampaignsOfCompanyWithDetails ($companyId: bigint!) {
  campaigns(where: {company_id: {_eq: $companyId}}) {
    name
    company {
      name
    }
    cost_model
    monthly_budget
    state
    ads (where: {company_id: {_eq: $companyId}}) {
      id
      campaign {
        name
      }
      clicks (where: {company_id: {_eq: $companyId}}) {
        clicked_at
        site_url
        cost_per_click_usd
      }
      impressions (where: {company_id: {_eq: $companyId}}) {
        seen_at
        site_url
        cost_per_impression_usd
      }
    }
  }
}

query AllClicksAndImpressionsOfCompany ($companyId: bigint!) {
  clicks (where: {company_id: {_eq: $companyId}}){
    cost_per_click_usd
    clicked_at
    site_url
    user_ip
    user_data
    ad {
      name
    }
  }
  impressions (where: {company_id: {_eq: $companyId}}) {
    cost_per_impression_usd
    seen_at
    site_url
    user_ip
    user_data
    ad {
      name
    }
  }
}

```

### Additional querying with Citus specific functions

Create views with complex SQL.

This is the same SQL as the last portion of this (section in Citus
docs)[https://docs.citusdata.com/en/v7.4/use_cases/multi_tenant.html#integrating-applications],
with some minor modifications to aggregate all companies.

```sql
CREATE OR REPLACE VIEW "campaign_ranks" AS
 SELECT a.campaign_id,
    rank() OVER (PARTITION BY a.campaign_id, a.company_id ORDER BY a.campaign_id, (count(*)) DESC) AS rank,
    count(*) AS n_impressions,
    a.id AS ad_id,
    a.company_id
   FROM ads a,
    impressions i
  WHERE ((i.company_id = a.company_id) AND (i.ad_id = a.id))
  GROUP BY a.campaign_id, a.id, a.company_id
  ORDER BY a.campaign_id, (count(*)) DESC;
```

Now we can query this view in our GraphQL query as well:

```graphql
query {
  campaign_ranks (where: {company_id: {_eq: 5}}) {
    campaign_id
    rank
    n_impressions
    ad_id
  }
}
```

## Errors/Failures

1. Following query does not work:

```graphql
query AdsOfACompany ($companyId: bigint!) {
  ads (where: {company_id: {_eq: $companyId}}) {
    name
    image_url
    campaign {
      name
      company {
        name
      }
    }
    impressions (where: {company_id: {_eq: $companyId}}) {
      cost_per_impression_usd
      seen_at
      site_url
    }
  }
}
```

Results in error:

```json
{
  "errors": [
    {
      "internal": {
        "statement": "SELECT  coalesce(json_agg(\"root\" ), '[]' ) AS \"root\" FROM  (SELECT  row_to_json((SELECT  \"_11_e\"  FROM  (SELECT  \"_0_root.base\".\"name\" AS \"name\", \"_0_root.base\".\"image_url\" AS \"image_url\", \"_6_root.or.campaign\".\"campaign\" AS \"campaign\", \"_10_root.ar.root.impressions\".\"impressions\" AS \"impressions\"       ) AS \"_11_e\"      ) ) AS \"root\" FROM  (SELECT  *  FROM \"public\".\"ads\"  WHERE (((\"public\".\"ads\".\"company_id\") = ($1)) OR (((\"public\".\"ads\".\"company_id\") IS NULL) AND (($1) IS NULL)))     ) AS \"_0_root.base\" LEFT OUTER JOIN LATERAL (SELECT  row_to_json((SELECT  \"_5_e\"  FROM  (SELECT  \"_1_root.or.campaign.base\".\"name\" AS \"name\", \"_4_root.or.campaign.or.company\".\"company\" AS \"company\"       ) AS \"_5_e\"      ) ) AS \"campaign\" FROM  (SELECT  *  FROM \"public\".\"campaigns\"  WHERE (((\"_0_root.base\".\"campaign_id\") = (\"id\")) AND ((\"_0_root.base\".\"company_id\") = (\"company_id\")))     ) AS \"_1_root.or.campaign.base\" LEFT OUTER JOIN LATERAL (SELECT  row_to_json((SELECT  \"_3_e\"  FROM  (SELECT  \"_2_root.or.campaign.or.company.base\".\"name\" AS \"name\"       ) AS \"_3_e\"      ) ) AS \"company\" FROM  (SELECT  *  FROM \"public\".\"companies\"  WHERE ((\"_1_root.or.campaign.base\".\"company_id\") = (\"id\"))     ) AS \"_2_root.or.campaign.or.company.base\"      ) AS \"_4_root.or.campaign.or.company\" ON ('true')      ) AS \"_6_root.or.campaign\" ON ('true') LEFT OUTER JOIN LATERAL (SELECT  coalesce(json_agg(\"impressions\" ), '[]' ) AS \"impressions\" FROM  (SELECT  row_to_json((SELECT  \"_8_e\"  FROM  (SELECT  \"_7_root.ar.root.impressions.base\".\"cost_per_impression_usd\" AS \"cost_per_impression_usd\", \"_7_root.ar.root.impressions.base\".\"seen_at\" AS \"seen_at\", \"_7_root.ar.root.impressions.base\".\"site_url\" AS \"site_url\"       ) AS \"_8_e\"      ) ) AS \"impressions\" FROM  (SELECT  *  FROM \"public\".\"impressions\"  WHERE ((((\"_0_root.base\".\"company_id\") = (\"company_id\")) AND ((\"_0_root.base\".\"id\") = (\"ad_id\"))) AND (((\"public\".\"impressions\".\"company_id\") = ($2)) OR (((\"public\".\"impressions\".\"company_id\") IS NULL) AND (($2) IS NULL))))     ) AS \"_7_root.ar.root.impressions.base\"      ) AS \"_9_root.ar.root.impressions\"      ) AS \"_10_root.ar.root.impressions\" ON ('true')      ) AS \"_12_root\"      ",
        "prepared": true,
        "error": {
          "exec_status": "FatalError",
          "hint": null,
          "message": "cannot push down this subquery",
          "status_code": "0A000",
          "description": "Aggregates without group by are currently unsupported when a subquery references a column from another query"
        },
        "arguments": [
          "(Oid 20,Just (\"\\NUL\\NUL\\NUL\\NUL\\NUL\\NUL\\NUL\\ENQ\",Binary))",
          "(Oid 20,Just (\"\\NUL\\NUL\\NUL\\NUL\\NUL\\NUL\\NUL\\ENQ\",Binary))"
        ]
      },
      "path": "$",
      "error": "postgres query error",
      "code": "postgres-error"
    }
  ]
}
```

2. Add object relationships in the `campaign_ranks` view, to the `campaigns` table and `ads` table.

```json
[
  {
    "using": {
      "manual_configuration": {
        "remote_table": "companies",
        "column_mapping": {
          "company_id": "id"
        }
      }
    },
    "name": "company",
    "comment": null
  },
  {
    "using": {
      "manual_configuration": {
        "remote_table": "ads",
        "column_mapping": {
          "ad_id": "id"
        }
      }
    },
    "name": "ad",
    "comment": null
  },
  {
    "using": {
      "manual_configuration": {
        "remote_table": "campaigns",
        "column_mapping": {
          "ad_id": "id"
        }
      }
    },
    "name": "campaign",
    "comment": null
  }
]
```

Then make this query:

```graphql
query {
  campaign_ranks (where: {company_id: {_eq: 5}}) {
    campaign {
      name
    }
    rank
    n_impressions
    ad {
      name
    }
  }
}
```

Fails with error:

```json
{
  "errors": [
    {
      "internal": {
        "statement": "SELECT  coalesce(json_agg(\"root\" ), '[]' ) AS \"root\" FROM  (SELECT  row_to_json((SELECT  \"_7_e\"  FROM  (SELECT  \"_6_root.or.campaign\".\"campaign\" AS \"campaign\", (\"_0_root.base\".\"rank\")::text AS \"rank\", (\"_0_root.base\".\"n_impressions\")::text AS \"n_impressions\", \"_3_root.or.ad\".\"ad\" AS \"ad\"       ) AS \"_7_e\"      ) ) AS \"root\" FROM  (SELECT  *  FROM \"public\".\"campaign_ranks\"  WHERE (((\"public\".\"campaign_ranks\".\"company_id\") = ($1)) OR (((\"public\".\"campaign_ranks\".\"company_id\") IS NULL) AND (($1) IS NULL)))     ) AS \"_0_root.base\" LEFT OUTER JOIN LATERAL (SELECT  row_to_json((SELECT  \"_2_e\"  FROM  (SELECT  \"_1_root.or.ad.base\".\"name\" AS \"name\"       ) AS \"_2_e\"      ) ) AS \"ad\" FROM  (SELECT  *  FROM \"public\".\"ads\"  WHERE ((\"_0_root.base\".\"ad_id\") = (\"id\"))     ) AS \"_1_root.or.ad.base\"      ) AS \"_3_root.or.ad\" ON ('true') LEFT OUTER JOIN LATERAL (SELECT  row_to_json((SELECT  \"_5_e\"  FROM  (SELECT  \"_4_root.or.campaign.base\".\"name\" AS \"name\"       ) AS \"_5_e\"      ) ) AS \"campaign\" FROM  (SELECT  *  FROM \"public\".\"campaigns\"  WHERE ((\"_0_root.base\".\"campaign_id\") = (\"id\"))     ) AS \"_4_root.or.campaign.base\"      ) AS \"_6_root.or.campaign\" ON ('true')      ) AS \"_8_root\"      ",
        "prepared": true,
        "error": {
          "exec_status": "FatalError",
          "hint": "Consider using an equality filter on the distributed table's partition column.",
          "message": "could not run distributed query with subquery outside the FROM and WHERE clauses",
          "status_code": "0A000",
          "description": null
        },
        "arguments": [
          "(Oid 20,Just (\"\\NUL\\NUL\\NUL\\NUL\\NUL\\NUL\\NUL\\ENQ\",Binary))"
        ]
      },
      "path": "$",
      "error": "postgres query error",
      "code": "postgres-error"
    }
  ]
}
```


3. Add permissions to the `companies` table:

Role: user
Query: select
Columns: all
Custom check: `{"id":{"_eq":"x-hasura-company-id"}}`

Then making query:

```graphql
query {
  companies (where: {id: {_eq: 5}}) {
    name
  }
}
```

With headers:

```
x-hasura-role: user
x-hasura-company-id: 5
```

Results in:

```json
{
  "errors": [
    {
      "path": "$",
      "error": "postgres query error",
      "code": "postgres-error"
    }
  ]
}
```

Docker logs output:
```
WARNING:  unrecognized configuration parameter "hasura.user"
CONTEXT:  while executing command on citus_worker_1:5432
{"timestamp":"2018-12-17T13:52:30.729+0000","level":"info","type":"http-log","detail":{"status":500,"query_hash":"166c2438e839e201bd91a57873629136a9ec1d92","http_version":"HTTP/1.1","query_execution_time":1.7499646e-2,"request_id":null,"url":"/v1alpha1/graphql","ip":"122.171.161.60","response_size":1006,"user":{"x-hasura-role":"user","x-hasura-company-id":"5"},"method":"POST","detail":{"error":{"internal":{"statement":"SELECT  coalesce(json_agg(\"root\" ), '[]' ) AS \"root\" FROM  (SELECT  row_to_json((SELECT  \"_1_e\"  FROM  (SELECT  \"_0_root.base\".\"name\" AS \"name\"       ) AS \"_1_e\"      ) ) AS \"root\" FROM  (SELECT  *  FROM \"public\".\"companies\"  WHERE ((((\"public\".\"companies\".\"id\") = (((current_setting('hasura.user')::json->>'x-hasura-company-id'))::bigint)) OR (((\"public\".\"companies\".\"id\") IS NULL) AND ((((current_setting('hasura.user')::json->>'x-hasura-company-id'))::bigint) IS NULL))) AND (((\"public\".\"companies\".\"id\") = ($1)) OR (((\"public\".\"companies\".\"id\") IS NULL) AND (($1) IS NULL))))     ) AS \"_0_root.base\"      ) AS \"_2_root\"      ","prepared":true,"error":{"exec_status":"FatalError","hint":null,"message":"could not receive query results","status_code":"XX000","description":null},"arguments":["(Oid 20,Just (\"\\NUL\\NUL\\NUL\\NUL\\NUL\\NUL\\NUL\\ENQ\",Binary))"]},"path":"$","error":"postgres query error","code":"postgres-error"},"request":"{\"query\":\"query {\\n  companies (where: {id: {_eq: 5}}) {\\n    name\\n  }\\n}\",\"variables\":null}"}}}

```
