# Running Hasura's GrapQL engine on various Postgres instances

# TimescaleDB

1. Follow the timescale tutorial to install and run a timescale db instance.
   (https://docs.timescale.com/v0.9/getting-started/installation/mac/installation-homebrew)

2. Follow this tutorial to import a sample dataset. Here we are using New York City taxicab data. (https://docs.timescale.com/v0.9/tutorials/tutorial-hello-nyc).
   Follow this tutorial till the point to import data.

3. Follow https://docs.hasura.io to run the GraphQL engine - with the
   correct database credentials pointing to your timescaledb instance.

4. Open the console `hasura console`, and track all the tables.

5. Create views with timescaledb specific functions, for timescale specific queries.

6. Use Run SQL in console to create these views and track them:

```sql
-- Average fare amount of rides with 2+ passengers by day
CREATE VIEW avg_fare_w_2_plus_passenger_by_day AS (
    SELECT date_trunc('day', pickup_datetime) as day, avg(fare_amount) as avg_fare
    FROM rides
    WHERE passenger_count > 1
    GROUP BY day ORDER BY day
);

-- Total number of rides by day for first 5 days
CREATE VIEW ride_count_by_day AS (
  SELECT date_trunc('day', pickup_datetime) as day, COUNT(*) FROM rides
    GROUP BY day ORDER BY day
);

-- Number of rides by 5 minute intervals
--   (using the TimescaleDB "time_bucket" function)
CREATE VIEW rides_in_5min_intervals AS (
SELECT time_bucket('5 minute', pickup_datetime) AS five_min_interval, count(*) as rides
  FROM rides
  GROUP BY five_min_interval ORDER BY five_min_interval
);
```

7. Once the above is done, then we can run GraphQL queries on these views.

```graphql
query {
  avg_fare_w_2_plus_passenger_by_day(limit: 10) {
    day
    avg_fare
  }
}

query FirstTenDaysWithRidesMoreThan30k {
  ride_count_by_day(limit: 10, where: {count : {_gt: 30000}}) {
    day
    count
  }
}

query NoOfRidesIn5minIntervalBefore02Jan {
  rides_in_5min_intervals(where: {five_min_interval:{_lt: "2016-01-02 00:00"}}) {
    five_min_interval
    rides
  }
}
```

# Citus DB
1. Create a citus cloud instance, or install your own citus db instance.
   (https://docs.citusdata.com/en/v7.4/installation/single_machine.html)

2. Follow this tutorial to import a sample dataset. (https://docs.citusdata.com/en/v7.4/use_cases/multi_tenant.html)
   Follow this tutorial till the point to import data.

3. Follow https://docs.hasura.io to run the GraphQL engine - with the
   correct database credentials pointing to your citus db instance.

4. Open the console `hasura console`, and track all the tables.

5. Add the hasuradb metadata from the file `citus/metadata.json`. It will add required relationships.

Alternatively:
From console, object relationship of campaign table to company table can be added. For other tables:

```json
{
    "type": "bulk",
    "args": [
        {
            "type": "create_object_relationship",
            "args": {
                "table": "ads",
                "name": "campaign",
                "using": {
                    "manual_configuration" : {
                        "remote_table" : "campaigns",
                        "column_mapping" : {
                            "campaign_id" : "id",
                            "company_id": "company_id"
                        }
                    }
                }
            }
        },
        {
            "type": "create_object_relationship",
            "args": {
                "table": "clicks",
                "name": "ad",
                "using": {
                    "manual_configuration" : {
                        "remote_table" : "ads",
                        "column_mapping" : {
                            "ad_id" : "id",
                            "company_id": "company_id"
                        }
                    }
                }
            }
        },
        {
            "type": "create_object_relationship",
            "args": {
                "table": "impressions",
                "name": "ad",
                "using": {
                    "manual_configuration" : {
                        "remote_table" : "ads",
                        "column_mapping" : {
                            "ad_id" : "id",
                            "company_id": "company_id"
                        }
                    }
                }
            }
        }

    ]
}
```

6. Then we can make graphql queries :

NOTE: `company_id` is required at top-level for all queries, because its the distribution column in citus.

```graphql
query AllCampaignsOfCompany5 {
  campaigns(where: {company_id: {_eq: 5}}) {
    name
    company {
      name
    }
    cost_model
    monthly_budget
    state
  }
}

query AllClicksAndImpressionsOfCompany5 {
  clicks (where: {company_id: {_eq: 5}}){
    cost_per_click_usd
    clicked_at
    site_url
    user_ip
    user_data
    ad {
      name
    }
  }
  impressions (where: {company_id: {_eq: 5}}) {
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

7. Create views with complex SQL:

This is the same SQL as the last portion of this section
https://docs.citusdata.com/en/v7.4/use_cases/multi_tenant.html#integrating-applications,
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

## Errors/Failures:

**Edit**: #1 works now:

~1. If we make queries like:~

```graphql
query AllClicksOfCompany5 {
  clicks (where: {company_id: {_eq: 5}}){
    cost_per_click_usd
    clicked_at
    site_url
    user_ip
    user_data
    ad {
      name
      campaign {
        name
      }
    }
  }
}
```

It results in error:

```json
{
  "errors": [
    {
      "internal": {
        "statement": "SELECT  coalesce(json_agg((SELECT  \"e\"  FROM  (SELECT  \"r\".\"cost_per_click_usd\" AS \"cost_per_click_usd\", \"r\".\"clicked_at\" AS \"clicked_at\", \"r\".\"site_url\" AS \"site_url\", \"r\".\"user_ip\" AS \"user_ip\", \"r\".\"user_data\" AS \"user_data\", \"r\".\"ad\" AS \"ad\"       ) AS \"e\"      ) ), '[]' )  FROM  (SELECT  \"l\".\"user_ip\" AS \"user_ip\", \"l\".\"cost_per_click_usd\" AS \"cost_per_click_usd\", \"l\".\"site_url\" AS \"site_url\", \"l\".\"clicked_at\" AS \"clicked_at\", \"l\".\"user_data\" AS \"user_data\", \"l\".\"__l_ad_ad_id\" AS \"__l_ad_ad_id\", \"l\".\"__l_ad_company_id\" AS \"__l_ad_company_id\", CASE WHEN (\"r\".\"__r_ad_id\") IS NULL THEN 'null' ELSE row_to_json((SELECT  \"e\"  FROM  (SELECT  \"r\".\"name\" AS \"name\", \"r\".\"campaign\" AS \"campaign\"       ) AS \"e\"      ) ) END AS \"ad\" FROM  (SELECT  \"user_ip\" AS \"user_ip\", \"cost_per_click_usd\" AS \"cost_per_click_usd\", \"site_url\" AS \"site_url\", \"clicked_at\" AS \"clicked_at\", \"user_data\" AS \"user_data\", \"ad_id\" AS \"__l_ad_ad_id\", \"company_id\" AS \"__l_ad_company_id\" FROM \"public\".\"clicks\"  WHERE (('true') AND (('true') AND (((((\"public\".\"clicks\".\"company_id\") = ($1)) OR (((\"public\".\"clicks\".\"company_id\") IS NULL) AND (($1) IS NULL))) AND ('true')) AND ('true'))))     ) AS \"l\" LEFT OUTER JOIN LATERAL (SELECT  \"l\".\"__r_ad_id\" AS \"__r_ad_id\", \"l\".\"name\" AS \"name\", \"l\".\"__l_campaign_campaign_id\" AS \"__l_campaign_campaign_id\", \"l\".\"__l_campaign_company_id\" AS \"__l_campaign_company_id\", CASE WHEN (\"r\".\"__r_campaign_id\") IS NULL THEN 'null' ELSE row_to_json((SELECT  \"e\"  FROM  (SELECT  \"r\".\"name\" AS \"name\"       ) AS \"e\"      ) ) END AS \"campaign\" FROM  (SELECT  \"id\" AS \"__r_ad_id\", \"name\" AS \"name\", \"campaign_id\" AS \"__l_campaign_campaign_id\", \"company_id\" AS \"__l_campaign_company_id\" FROM \"public\".\"ads\"  WHERE ((((\"l\".\"__l_ad_ad_id\") = (\"id\")) AND (((\"l\".\"__l_ad_company_id\") = (\"company_id\")) AND ('true'))) AND (('true') AND ('true')))     ) AS \"l\" LEFT OUTER JOIN LATERAL (SELECT  \"id\" AS \"__r_campaign_id\", \"name\" AS \"name\" FROM \"public\".\"campaigns\"  WHERE ((((\"l\".\"__l_campaign_campaign_id\") = (\"id\")) AND (((\"l\".\"__l_campaign_company_id\") = (\"company_id\")) AND ('true'))) AND (('true') AND ('true')))     ) AS \"r\" ON ('true')      ) AS \"r\" ON ('true')      ) AS \"r\"      ",
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
      "path": "$[0].args",
      "error": "postgres query error",
      "code": "postgres-error"
    }
  ]
}
```

2. If we add relationships in the `campaign_ranks` view, like so:

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

Then this query fails:

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

With this error:

```json
{
  "errors": [
    {
      "internal": {
        "statement": "SELECT  coalesce(json_agg(json_build_object('campaign', \"r\".\"campaign\", 'rank', \"r\".\"rank\", 'n_impressions', \"r\".\"n_impressions\" ) ), '[]' )  FROM  (SELECT  \"l\".\"rank\" AS \"rank\", \"l\".\"n_impressions\" AS \"n_impressions\", \"l\".\"__l_campaign_ad_id\" AS \"__l_campaign_ad_id\", CASE WHEN (\"r\".\"__r_campaign_id\") IS NULL THEN 'null' ELSE json_build_object('name', \"r\".\"name\" ) END AS \"campaign\" FROM  (SELECT  \"rank\" AS \"rank\", \"n_impressions\" AS \"n_impressions\", \"ad_id\" AS \"__l_campaign_ad_id\" FROM \"public\".\"campaign_ranks\"  WHERE (('true') AND (('true') AND (((((\"public\".\"campaign_ranks\".\"company_id\") = ($1)) OR (((\"public\".\"campaign_ranks\".\"company_id\") IS NULL) AND (($1) IS NULL))) AND ('true')) AND ('true'))))     ) AS \"l\" LEFT OUTER JOIN LATERAL (SELECT  \"id\" AS \"__r_campaign_id\", \"name\" AS \"name\" FROM \"public\".\"campaigns\"  WHERE ((((\"l\".\"__l_campaign_ad_id\") = (\"id\")) AND ('true')) AND (('true') AND ('true')))     ) AS \"r\" ON ('true')      ) AS \"r\"      ",
        "prepared": true,
        "error": {
          "exec_status": "FatalError",
          "hint": null,
          "message": "complex joins are only supported when all distributed tables are joined on their distribution columns with equal operator",
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
