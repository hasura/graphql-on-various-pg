# Citus DB

Hasura on Citus. This uses Citus 8.0 and Hasura v1.0.0-alpha31.

## Setup

### Pre-requisites

1. docker-compose
2. psql

### Run citus and hasura 

1. Download the `docker-compose.yaml` file

```shell
$ curl -o ...
```

2. Run `docker-compose -p citus up -d`

This will start a Citus cluster with one worker, and a Hasura GraphQL Engine pointing to the citus instance.

### Import sample data from Citus multi-tenant example app dataset

1. Download the `load_sample_data.sh` and run it to load sample data into the citus instance.

```shell
$ curl -o ....
$ chmod +x load_sample_data.sh && ./load_sample_data.sh
```

### Add hasura metadata

1. Open the console
2. Track all the tables
3. Create relationships mentioned below, or use the `metadata.json` file to import the relationships. 


## The schema

All the tables are distributed tables. The distribution column is `company_id` (`id` in the `companies` table).

The rest of the tables has the following schema:

1. `companies`
2. `campaigns` :: has foreign key ref to `companies` via `company_id`
3. `ads` :: has foreign key ref to `campaigns` via `campaign_id` and `companies` via `company_id`
4. `clicks` :: has foreign key ref to `ads` via `ad_id` and `companies` via `company_id`
5. `impressions` :: has foreign key ref to `ads` via `ad_id` and `companies` via `company_id`

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

We can also add object relationships in the `campaign_ranks` view, to the `campaigns` table and `ads` table.

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
