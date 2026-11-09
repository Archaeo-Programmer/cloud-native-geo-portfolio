# Buildings in FEMA flood zones (Connecticut)

Status: in progress.

## Problem

FEMA's National Flood Hazard Layer ships as zipped shapefiles per county, which are slow
to join against other data. How many buildings sit in high-risk flood zones?

## Data

- FEMA NFHL flood hazard zones, processed with the
  [nfhl-geoparquet-workshop](https://github.com/gsueur/nfhl-geoparquet-workshop) pipeline
- [Overture Maps](https://overturemaps.org) building footprints, release 2026-10-21.0, downloaded
  with `overturemaps download` for the Middlesex County extent (-72.76, 41.25, -72.30, 41.65):
  139,098 buildings in a 25 MB GeoParquet file, fetched in about 6 seconds.
  133,415 come from OpenStreetMap and 5,683 from Microsoft ML Buildings.

### Data notes

- The FEMA zones are in NAD83 (EPSG:4269) and Overture is in WGS84 (OGC:CRS84). DuckDB 1.5
  refuses to join geometries in different coordinate systems, so the zones are converted with
  `ST_Transform(geometry, 'EPSG:4269', 'OGC:CRS84', always_xy := true)`. Without `always_xy`,
  longitude and latitude come out swapped.
- The download area is a rectangle, so it includes some buildings outside the county.

## Approach

To do.

## Result

Early benchmark from the workshop run: a point lookup took 0.09 ms with an R-tree index
versus 78.63 ms without (about 870 times faster).

## Deliverable

To do.

## Next steps

To do.
