-- Count Overture buildings by FEMA flood zone, New Haven County, CT
-- Run with:  duckdb < scripts/02_count_buildings.sql    (from the phase1-flood-buildings folder)
INSTALL spatial; LOAD spatial;

-- 1. Flood zones, converted from NAD83 to WGS84 (always_xy keeps lon/lat order)
CREATE TABLE zones AS
  SELECT * REPLACE (ST_Transform(geometry, 'EPSG:4269', 'OGC:CRS84', always_xy := true) AS geometry)
  FROM '../../FEMA/nfhl-geoparquet-workshop/data/silver_subdivided/state=CT/county=New Haven.parquet';

-- 2. Buildings: only the columns we need
CREATE TABLE bldg AS SELECT id, geometry FROM 'data/newhaven_buildings.parquet';

-- 3. Buildings per flood zone
SELECT z.flood_zone, z.sfha, count(DISTINCT b.id) AS buildings
FROM bldg b JOIN zones z ON ST_Intersects(b.geometry, z.geometry)
GROUP BY ALL ORDER BY buildings DESC;
