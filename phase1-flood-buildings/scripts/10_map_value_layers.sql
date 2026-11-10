-- Two map layers for QGIS showing assessed BUILDING value at risk (structures only, not land).
-- Input: newhaven_sfha_buildings_parcels.parquet (from scripts/09_join_parcels.sql), all at-risk buildings (touch rule).
-- Outputs (local, not in git):
--   map_buildings_value.parquet  one row per at-risk building; the main building on each parcel carries
--                                the parcel's building value, other buildings on that parcel are "secondary"
--   map_hex_value.parquet        H3 hexagons (resolution 8, about 0.7 km2) with total building value,
--                                each parcel counted once, placed by its main building
-- Run with:  duckdb < scripts/10_map_value_layers.sql
INSTALL spatial; LOAD spatial;
INSTALL h3 FROM community; LOAD h3;
.timer on

CREATE TABLE b AS SELECT * FROM 'data/newhaven_sfha_buildings_parcels.parquet';

-- 1. Main building per parcel = the largest footprint (avoids shading a garage with the house's value)
CREATE TABLE ranked AS
  SELECT *, row_number() OVER (PARTITION BY parcel_id ORDER BY ST_Area(geometry) DESC) AS size_rank
  FROM b;

CREATE TABLE buildings_value AS
  SELECT id, town, use_group, center_in_sfha, sfha_zones,
         CASE WHEN match_status = 'matched' AND size_rank = 1 THEN CAST(Assessed_Building AS BIGINT) END AS building_value,
         CASE
           WHEN match_status <> 'matched' OR Assessed_Building IS NULL THEN '0 No assessor data'
           WHEN size_rank > 1 THEN '0 Secondary building on parcel'
           WHEN Assessed_Building < 100000 THEN '1 Under $100k'
           WHEN Assessed_Building < 250000 THEN '2 $100k to $250k'
           WHEN Assessed_Building < 500000 THEN '3 $250k to $500k'
           WHEN Assessed_Building < 1000000 THEN '4 $500k to $1M'
           ELSE '5 Over $1M'
         END AS value_class,
         geometry
  FROM ranked;

COPY (SELECT * FROM buildings_value) TO 'data/map_buildings_value.parquet' (FORMAT parquet, COMPRESSION zstd);

-- 2. Hexagons: each parcel's building value, once, at its main building's interior point
CREATE TABLE hex AS
  SELECT h3_latlng_to_cell(ST_Y(pt), ST_X(pt), 8) AS h3_cell,
         count(*) AS parcels,
         sum(building_value) AS building_value
  FROM (SELECT ST_PointOnSurface(geometry) AS pt, building_value
        FROM buildings_value WHERE building_value IS NOT NULL)
  GROUP BY 1;

COPY (
  SELECT h3_h3_to_string(h3_cell) AS h3_cell, parcels, building_value,
         round(building_value / 1e6, 1) AS building_value_millions,
         ST_SetCRS(ST_GeomFromText(h3_cell_to_boundary_wkt(h3_cell)), 'OGC:CRS84') AS geometry
  FROM hex
) TO 'data/map_hex_value.parquet' (FORMAT parquet, COMPRESSION zstd);

-- 3. Checks
SELECT value_class, count(*) AS buildings FROM buildings_value GROUP BY 1 ORDER BY 1;
SELECT count(*) AS hexagons, sum(parcels) AS parcels, round(sum(building_value) / 1e9, 2) AS building_value_billions,
       round(max(building_value) / 1e6, 1) AS largest_hex_millions
FROM 'data/map_hex_value.parquet';
