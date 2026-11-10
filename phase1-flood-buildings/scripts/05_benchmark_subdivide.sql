-- Benchmark: the same question on FEMA's original polygons vs. the subdivided pieces.
-- Run with:  duckdb < scripts/05_benchmark_subdivide.sql    (from the phase1-flood-buildings folder)
-- Question: how many New Haven County buildings touch the 1% flood zone (SFHA)?
INSTALL spatial; LOAD spatial;
.timer on

CREATE TABLE bldg AS SELECT id, geometry FROM 'data/newhaven_buildings.parquet';

-- A. FEMA's original polygons (bronze): 6,881 polygons, the largest with 160,383 vertices
CREATE TABLE zones_original AS
  SELECT ST_Transform(geometry, 'EPSG:4269', 'OGC:CRS84', always_xy := true) AS geometry
  FROM '../../FEMA/nfhl-geoparquet-workshop/data/bronze/state=CT/county=New Haven/S_FLD_HAZ_AR.parquet'
  WHERE SFHA_TF = 'T';

-- B. The same zones subdivided to at most 100 vertices per piece
CREATE TABLE zones_subdivided AS
  SELECT ST_Transform(geometry, 'EPSG:4269', 'OGC:CRS84', always_xy := true) AS geometry
  FROM '../../FEMA/nfhl-geoparquet-workshop/data/silver_subdivided/state=CT/county=New Haven.parquet'
  WHERE sfha;

-- Run A: original polygons
SELECT 'original' AS zones, count(DISTINCT b.id) AS buildings
FROM bldg b JOIN zones_original z ON ST_Intersects(b.geometry, z.geometry);

-- Run B: subdivided pieces
SELECT 'subdivided' AS zones, count(DISTINCT b.id) AS buildings
FROM bldg b JOIN zones_subdivided z ON ST_Intersects(b.geometry, z.geometry);
