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
