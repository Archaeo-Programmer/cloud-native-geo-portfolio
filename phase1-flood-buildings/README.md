# Buildings in FEMA flood zones (New Haven County, Connecticut)

Status: in progress.

## Problem

FEMA's National Flood Hazard Layer ships as zipped shapefiles per county, which are slow
to join against other data. How many buildings in New Haven County sit in high-risk flood zones?

## Data

- FEMA NFHL flood hazard zones, processed with the
  [nfhl-geoparquet-workshop](https://github.com/gsueur/nfhl-geoparquet-workshop) pipeline
- [Overture Maps](https://overturemaps.org) building footprints, release 2026-10-21.0, downloaded
  with `overturemaps download` for New Haven County's extent (-73.327, 41.164, -72.534, 41.644),
  taken from the flood-zone data with `ST_Extent_Agg`: 582,882 buildings in a 103 MB GeoParquet
  file, fetched in about 8 seconds.

### Data notes

- The FEMA zones are in NAD83 (EPSG:4269) and Overture is in WGS84 (OGC:CRS84). DuckDB 1.5
  refuses to join geometries in different coordinate systems, so the zones are converted with
  `ST_Transform(geometry, 'EPSG:4269', 'OGC:CRS84', always_xy := true)`. Without `always_xy`,
  longitude and latitude come out swapped.
- The download area is a rectangle, so it includes buildings in neighboring counties. FEMA's map
  covers the whole county (minimal-risk land is Zone X), so the join keeps only New Haven buildings:
  333,165 of the 582,882.
- A building on a zone boundary touches several zones, so counts by zone overlap. The risk table
  counts each building once, under its highest risk.

## Approach

1. Process the NFHL for Connecticut into GeoParquet with the workshop pipeline (bronze, silver,
   subdivided to at most 100 vertices per polygon).
2. Get the county's bounding box from the flood zones (`ST_Extent_Agg`).
3. Download Overture buildings for that box (`overturemaps download`).
4. Convert the zones to WGS84 and join with `ST_Intersects` in DuckDB
   ([count_buildings.sql](count_buildings.sql), [count_by_risk.sql](count_by_risk.sql)).

## Result

About **13,000 to 16,000 of New Haven County's 333,000 buildings** sit in FEMA's
1%-annual-chance flood zone (the Special Flood Hazard Area). The range comes from how a building
counts as "in" the zone:

| Rule | 1% flood zone | 0.2% flood zone | Buildings in county |
| --- | --- | --- | --- |
| Any part of the footprint touches the zone ([count_by_risk.sql](count_by_risk.sql)) | 15,958 (4.8%) | 4,207 (1.3%) | 333,165 |
| A point inside the footprint is in the zone ([count_by_risk_point.sql](count_by_risk_point.sql)) | 12,953 (3.9%) | 3,693 (1.1%) | 333,117 |

About 3,000 buildings (19% of the upper count) are edge cases: the floodplain clips part of the
footprint but not its interior. Which number to use depends on the question. An insurer or
emergency planner would want the upper bound, and a planning or assessment report would more
likely use the point rule. The point is made with `ST_PointOnSurface`, which, unlike
`ST_Centroid`, always falls inside the building, even for L- or U-shaped footprints.

Each building is counted once, under its highest risk. By FEMA zone code (touch rule, overlapping):
X 321,858; AE 14,187; VE 1,361 (coastal wave action); A 1,054; AO 9. Each county-wide join runs in
under a second on a laptop. Results: [results_by_risk.csv](results_by_risk.csv),
[results_by_risk_point.csv](results_by_risk_point.csv).

Overture includes outbuildings such as sheds, and coverage depends on OpenStreetMap.

Early benchmark from the workshop run: a point lookup took 0.09 ms with an R-tree index
versus 78.63 ms without (about 870 times faster).

## Deliverable

To do.

## Next steps

- Save the 1% zone buildings as Hilbert-sorted GeoParquet and map them.
