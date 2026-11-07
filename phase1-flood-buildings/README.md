# Buildings in FEMA flood zones (Connecticut)

Status: in progress.

## Problem

FEMA's National Flood Hazard Layer ships as zipped shapefiles per county, which are slow
to join against other data. How many buildings sit in high-risk flood zones?

## Data

- FEMA NFHL flood hazard zones, processed with the
  [nfhl-geoparquet-workshop](https://github.com/gsueur/nfhl-geoparquet-workshop) pipeline
- [Overture Maps](https://overturemaps.org) building footprints

## Approach

To do.

## Result

Early benchmark from the workshop run: a point lookup took 0.09 ms with an R-tree index
versus 78.63 ms without (about 870 times faster).

## Deliverable

To do.

## Next steps

To do.
