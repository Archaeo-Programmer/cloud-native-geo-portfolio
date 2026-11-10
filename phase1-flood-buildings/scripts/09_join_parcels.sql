-- Give each at-risk building the use, value and age of the parcel it sits on.
-- Inputs: newhaven_sfha_buildings.parquet (Step 6) and newhaven_parcels.parquet (CT CAMA 2025).
-- Rules:
--   1. A building belongs to the parcel holding the largest share of its footprint.
--   2. Near-ties (within 5 percentage points): prefer a parcel with assessor data, then the smaller one.
--   3. If the chosen parcel has no assessor data, the building gets none (no borrowing from neighbors).
--   4. Values are summed once per parcel, never once per building.
-- Headline value = assessed BUILDING value (what a flood can damage); total assessed value
-- (land + buildings) is kept as context. CT assesses property at 70% of market value.
-- Run with:  duckdb < scripts/09_join_parcels.sql
INSTALL spatial; LOAD spatial;
.timer on

-- Parcels: repair the few broken shapes, flag assessor data, group the use codes
CREATE TABLE p AS
  SELECT OBJECTID AS parcel_id, Town_Name AS town, State_Use, State_Use_Description AS use_desc,
         Assessed_Total, Assessed_Building, AYB AS year_built, Living_Area, Occupancy,
         (State_Use_Description IS NOT NULL OR coalesce(Assessed_Total, 0) > 0) AS has_data,
         CASE
           WHEN State_Use IS NULL THEN 'Unknown'
           WHEN left(State_Use, 1) = '1' AND upper(State_Use_Description) LIKE '%CONDO%' THEN 'Residential: condominium'
           WHEN left(State_Use, 1) = '1' AND regexp_matches(upper(State_Use_Description),
                'TWO|THREE|FOUR|2 FAM|3 FAM|MULTI|APT|APART') THEN 'Residential: multi-family'
           WHEN left(State_Use, 1) = '1' THEN 'Residential: single-family and other'
           WHEN left(State_Use, 1) IN ('2', '3') THEN 'Commercial'
           WHEN left(State_Use, 1) = '4' THEN 'Industrial'
           WHEN left(State_Use, 1) = '9' THEN 'Government and tax-exempt'
           ELSE 'Other (vacant, farm, recreation)'
         END AS use_group,
         ST_Area(geometry) AS parcel_area,
         CASE WHEN ST_IsValid(geometry) THEN geometry ELSE ST_MakeValid(geometry) END AS geometry
  FROM 'data/newhaven_parcels.parquet';

CREATE TABLE b AS SELECT * FROM 'data/newhaven_sfha_buildings.parquet';

-- Share of each building's footprint inside each parcel it touches
CREATE TABLE shares AS
  SELECT b.id, p.parcel_id, p.has_data, p.parcel_area,
         ST_Area(ST_Intersection(b.geometry, p.geometry)) / ST_Area(b.geometry) AS share
  FROM b JOIN p ON ST_Intersects(b.geometry, p.geometry);

-- Apply rules 1-3: rank candidates, keep the top one per building
CREATE TABLE pick AS
  SELECT id, parcel_id, share, has_data FROM (
    SELECT s.*,
           row_number() OVER (PARTITION BY id ORDER BY
             (share >= top - 0.05) DESC,   -- the largest share, or a near-tie with it
             (share >= top - 0.05 AND has_data) DESC,
             CASE WHEN share >= top - 0.05 THEN parcel_area END ASC,
             share DESC) AS rank
    FROM shares s JOIN (SELECT id, max(share) AS top FROM shares GROUP BY id) USING (id))
  WHERE rank = 1;

-- One row per at-risk building, with its parcel's attributes when it has assessor data
CREATE TABLE out AS
  SELECT b.* EXCLUDE (geometry),
         CASE WHEN pk.parcel_id IS NULL THEN 'no parcel'
              WHEN NOT pk.has_data THEN 'no assessor data'
              ELSE 'matched' END AS match_status,
         round(pk.share, 3) AS footprint_share,
         p.parcel_id, p.town, p.use_group, p.use_desc, p.Assessed_Total, p.Assessed_Building,
         p.year_built, p.Living_Area, p.Occupancy,
         b.geometry
  FROM b
  LEFT JOIN pick pk USING (id)
  LEFT JOIN p ON p.parcel_id = pk.parcel_id AND pk.has_data;

COPY (SELECT * FROM out ORDER BY ST_Hilbert(geometry, (SELECT ST_Extent(ST_Extent_Agg(geometry)) FROM out)))
  TO 'data/newhaven_sfha_buildings_parcels.parquet' (FORMAT parquet, COMPRESSION zstd);

-- Coverage
SELECT match_status, count(*) AS buildings, round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM out GROUP BY 1 ORDER BY 2 DESC;

-- By use: buildings, parcels and value (value once per parcel). "strict" = point-inside rule; "ve" = wave zone
COPY (
  WITH parcel_flags AS (
    SELECT parcel_id, any_value(use_group) AS use_group,
           CAST(any_value(Assessed_Building) AS BIGINT) AS bvalue, any_value(Assessed_Total) AS tvalue,
           bool_or(center_in_sfha) AS strict, bool_or(list_contains(sfha_zones, 'VE')) AS ve
    FROM out WHERE match_status = 'matched' GROUP BY parcel_id)
  SELECT u.use_group,
         u.buildings, u.buildings_strict, u.buildings_ve, f.parcels,
         f.building_value, f.building_value_strict, f.building_value_ve,
         f.total_assessed_value
  FROM (SELECT use_group, count(*) AS buildings, count(*) FILTER (WHERE center_in_sfha) AS buildings_strict,
               count(*) FILTER (WHERE list_contains(sfha_zones, 'VE')) AS buildings_ve
        FROM out WHERE match_status = 'matched' GROUP BY 1) u
  JOIN (SELECT use_group, count(*) AS parcels,
               sum(bvalue) AS building_value,
               sum(bvalue) FILTER (WHERE strict) AS building_value_strict,
               sum(bvalue) FILTER (WHERE ve) AS building_value_ve,
               sum(tvalue) AS total_assessed_value
        FROM parcel_flags GROUP BY 1) f USING (use_group)
  ORDER BY building_value DESC NULLS LAST
) TO 'results/by_use.csv' (HEADER);

-- By town (value once per parcel)
COPY (
  SELECT town, count(*) AS parcels, sum(n_buildings) AS buildings,
         sum(bvalue) AS building_value, sum(tvalue) AS total_assessed_value
  FROM (SELECT parcel_id, any_value(town) AS town, CAST(any_value(Assessed_Building) AS BIGINT) AS bvalue,
               any_value(Assessed_Total) AS tvalue, count(*) AS n_buildings
        FROM out WHERE match_status = 'matched' GROUP BY parcel_id)
  GROUP BY town ORDER BY building_value DESC NULLS LAST
) TO 'results/by_town.csv' (HEADER);

-- By period built (buildings; year 0 or missing counted as unknown)
COPY (
  SELECT CASE WHEN year_built IS NULL OR year_built < 1700 THEN 'Unknown'
              WHEN year_built < 1900 THEN 'Before 1900'
              WHEN year_built < 1950 THEN '1900-1949'
              WHEN year_built < 1980 THEN '1950-1979'
              WHEN year_built < 2000 THEN '1980-1999'
              ELSE '2000 or later' END AS period_built,
         count(*) AS buildings
  FROM out WHERE match_status = 'matched' GROUP BY 1 ORDER BY 1
) TO 'results/by_period_built.csv' (HEADER);

SELECT use_group, buildings, parcels, building_value, building_value_ve, total_assessed_value FROM 'results/by_use.csv';

-- Totals (value once per parcel)
SELECT sum(building_value) AS building_value, sum(building_value_strict) AS building_value_strict,
       sum(building_value_ve) AS building_value_ve, sum(total_assessed_value) AS total_assessed_value
FROM 'results/by_use.csv';
