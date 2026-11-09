-- Step 6: write New Haven County buildings in FEMA's 1% flood zone (SFHA) as GeoParquet.
-- One row per building that touches the SFHA; center_in_sfha marks the stricter point-inside rule.
INSTALL spatial; LOAD spatial;

-- 1. Only the high-risk zones (sfha = true), converted to WGS84 like before
CREATE TABLE sfha_zones AS
  SELECT flood_zone,
         ST_Transform(geometry, 'EPSG:4269', 'OGC:CRS84', always_xy := true) AS geometry
  FROM '../../FEMA/nfhl-geoparquet-workshop/data/silver_subdivided/state=CT/county=New Haven.parquet'
  WHERE sfha;

-- 2. Buildings with the attributes worth keeping
CREATE TABLE bldg AS
  SELECT id, subtype, class, height, num_floors,
         names.primary AS name,
         sources[1].dataset AS source,
         geometry
  FROM 'newhaven_buildings.parquet';

-- 3. For each building touching the SFHA: which zone codes, and is a point inside it in the zone?
CREATE TABLE hits AS
  SELECT b.id,
         list(DISTINCT z.flood_zone ORDER BY z.flood_zone) AS sfha_zones,
         bool_or(ST_Within(ST_PointOnSurface(b.geometry), z.geometry)) AS center_in_sfha
  FROM bldg b JOIN sfha_zones z ON ST_Intersects(b.geometry, z.geometry)
  GROUP BY b.id;

-- 4. Join the attributes back, sort along a Hilbert curve using the data's own extent, write the file
CREATE TABLE out AS
  SELECT b.id, b.subtype, b.class, b.height, b.num_floors, b.name, b.source,
         h.sfha_zones, h.center_in_sfha, b.geometry
  FROM bldg b JOIN hits h USING (id);

COPY (
  SELECT * FROM out
  ORDER BY ST_Hilbert(geometry, (SELECT ST_Extent(ST_Extent_Agg(geometry)) FROM out))
) TO 'newhaven_sfha_buildings.parquet' (FORMAT parquet, COMPRESSION zstd);

-- 5. Self-check: these should match the earlier results (15,958 touching, 12,953 point-inside)
SELECT count(*) AS buildings,
       count(*) FILTER (WHERE center_in_sfha) AS center_in_sfha
FROM 'newhaven_sfha_buildings.parquet';
