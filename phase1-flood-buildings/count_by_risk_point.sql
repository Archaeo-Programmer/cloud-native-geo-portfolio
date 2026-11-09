-- Each building counted once, using a point inside its footprint (New Haven County, CT)
INSTALL spatial; LOAD spatial;
CREATE TABLE zones AS
  SELECT * REPLACE (ST_Transform(geometry, 'EPSG:4269', 'OGC:CRS84', always_xy := true) AS geometry)
  FROM '../../FEMA/nfhl-geoparquet-workshop/data/silver_subdivided/state=CT/county=New Haven.parquet';
CREATE TABLE bldg AS SELECT id, geometry FROM 'newhaven_buildings.parquet';

-- All building-zone pairs, then keep each building's worst risk
CREATE TABLE pairs AS
  SELECT b.id, z.risk, z.sfha,
         CASE z.risk WHEN '1 percent flood zone' THEN 3
                     WHEN '0.2 percent flood zone' THEN 2
                     WHEN 'water' THEN 1 ELSE 0 END AS risk_rank
  FROM bldg b JOIN zones z ON ST_Within(ST_PointOnSurface(b.geometry), z.geometry);

COPY (SELECT risk, count(*) AS buildings, round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM (SELECT id, arg_max(risk, risk_rank) AS risk FROM pairs GROUP BY id)
GROUP BY risk ORDER BY buildings DESC) TO 'results_by_risk_point.csv' (HEADER);

SELECT * FROM 'results_by_risk_point.csv';

SELECT count(DISTINCT id) AS buildings_in_county,
       count(DISTINCT id) FILTER (WHERE sfha) AS buildings_in_sfha
FROM pairs;
