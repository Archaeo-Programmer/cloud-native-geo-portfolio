-- Public-columns-only copy of the at-risk buildings as GeoParquet 2.0, the input for the
-- PMTiles-in-GeoParquet test (gsueur/geoparquet-pmtiles). No parcel IDs or exact values,
-- only the banded value class already used on the New Haven Harbor map.
-- Input: data/map_buildings_value.parquet (from scripts/10_map_value_layers.sql).
-- Adds a bbox struct column (the tiler pipeline sorts and pages by it) and labels the CRS.
-- GEOPARQUET_VERSION 'V2' makes DuckDB write a native Parquet GEOMETRY column (GeoParquet 2.0)
-- instead of plain WKB bytes (GeoParquet 1.0), which is what the pipeline expects.
-- Run with:  duckdb < scripts/11_export_public_buildings.sql    (from the phase1-flood-buildings folder)
INSTALL spatial; LOAD spatial;

COPY (
  SELECT id, town, use_group, center_in_sfha,
         list_aggr(sfha_zones, 'string_agg', ',') AS sfha_zones,   -- list -> text; vector tiles can't hold lists
         value_class,
         {'xmin': ST_XMin(geometry), 'ymin': ST_YMin(geometry),
          'xmax': ST_XMax(geometry), 'ymax': ST_YMax(geometry)} AS bbox,
         ST_SetCRS(geometry, 'OGC:CRS84') AS geometry
  FROM 'data/map_buildings_value.parquet'
) TO 'data/newhaven_sfha_buildings_public.parquet' (FORMAT parquet, COMPRESSION zstd, GEOPARQUET_VERSION 'V2');

-- Check: 15,958 buildings, 7 value classes
SELECT count(*) AS buildings, count(DISTINCT value_class) AS classes
FROM 'data/newhaven_sfha_buildings_public.parquet';
