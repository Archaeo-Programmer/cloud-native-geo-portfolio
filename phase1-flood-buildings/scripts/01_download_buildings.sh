#!/usr/bin/env bash
# Step 1: download Overture Maps building footprints for New Haven County, CT, as GeoParquet.
# The bounding box (west, south, east, north) is New Haven County's extent, taken from the
# FEMA flood zones with ST_Extent_Agg. Release used in the case study: 2026-10-21.0.
# Run with:  bash scripts/01_download_buildings.sh    (from the phase1-flood-buildings folder)
set -euo pipefail
mkdir -p data
uvx overturemaps download \
  --bbox=-73.327,41.164,-72.534,41.644 \
  -f geoparquet -t building \
  -r 2026-10-21.0 \
  -o data/newhaven_buildings.parquet
