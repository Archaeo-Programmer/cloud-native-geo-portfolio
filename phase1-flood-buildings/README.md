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

Of **333,165 buildings** in New Haven County, **15,958 (4.8%)** touch FEMA's 1%-annual-chance flood
zone and another **4,207 (1.3%)** touch the 0.2% zone ([results_by_risk.csv](results_by_risk.csv)).

| Highest flood risk | Buildings | Share |
| --- | --- | --- |
| Minimal | 313,000 | 93.9% |
| 1 percent flood zone (SFHA) | 15,958 | 4.8% |
| 0.2 percent flood zone | 4,207 | 1.3% |

By FEMA zone (overlapping): X 321,858; AE 14,187; VE 1,361 (coastal wave action); A 1,054; AO 9.
The whole county join runs in under a second on a laptop.

"Touches" is an upper bound: a building partly in the zone counts. Overture includes outbuildings
such as sheds, and coverage depends on OpenStreetMap.

Early benchmark from the workshop run: a point lookup took 0.09 ms with an R-tree index
versus 78.63 ms without (about 870 times faster).

## Deliverable

To do.

## Next steps

- Compare with a stricter rule: count a building only if its center point is in the zone.
- Save the 1% zone buildings as Hilbert-sorted GeoParquet and map them.
