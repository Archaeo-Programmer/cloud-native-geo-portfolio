-- Convert the downloaded parcel pages (GeoJSON) into one GeoParquet file.
-- Source: Connecticut CAMA and Parcel Layer 2025 (CT GIS Office), New Haven County's 27 towns.
-- No owner or address fields were downloaded (see scripts/07_fetch_parcels.py).
-- Run with:  duckdb < scripts/08_convert_parcels.sql      (note: < feeds the file in; > would overwrite it)
INSTALL spatial; LOAD spatial;
.timer on

-- 1. Read every page; one row per parcel
CREATE TABLE raw AS
  SELECT unnest(features) AS f
  FROM read_json('data/parcels_raw/*.geojson', maximum_object_size = 200000000);

-- 2. Attributes as columns, geometry as real shapes labeled with Overture's coordinate system
CREATE TABLE parcels AS
  SELECT unnest(f.properties),   -- expand the attribute fields into columns
         ST_SetCRS(ST_GeomFromGeoJSON(to_json(f.geometry)), 'OGC:CRS84') AS geometry
  FROM raw
  WHERE f.geometry IS NOT NULL;

-- 3. Write Hilbert-sorted, compressed GeoParquet
COPY (
  SELECT * FROM parcels
  ORDER BY ST_Hilbert(geometry, (SELECT ST_Extent(ST_Extent_Agg(geometry)) FROM parcels))
) TO 'data/newhaven_parcels.parquet' (FORMAT parquet, COMPRESSION zstd);

-- 4. Checks: how many parcels (and how many had no shape), and a peek by town
SELECT (SELECT count(*) FROM raw) AS downloaded,
       (SELECT count(*) FROM parcels) AS with_geometry;
SELECT Town_Name, count(*) AS parcels FROM 'data/newhaven_parcels.parquet'
GROUP BY 1 ORDER BY parcels DESC LIMIT 5;
