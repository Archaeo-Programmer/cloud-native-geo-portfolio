"""Download New Haven County parcels with assessor (CAMA) attributes from the
Connecticut CAMA and Parcel Layer 2025 (CT GIS Office, public domain).

Owner names, mailing addresses and street addresses are never requested.
Pages of 2,000 parcels are saved to data/parcels_raw/ so a rerun resumes
where it stopped. Run: python3 fetch_parcels.py
"""
import json
import pathlib
import time
import urllib.parse
import urllib.request

BASE = ("https://services3.arcgis.com/3FL1kr7L4LvwA2Kb/arcgis/rest/services/"
        "Connecticut_CAMA_and_Parcel_Layer_2025/FeatureServer/0/query")
TOWNS = ["Ansonia", "Beacon Falls", "Bethany", "Branford", "Cheshire", "Derby",
         "East Haven", "Guilford", "Hamden", "Madison", "Meriden", "Middlebury",
         "Milford", "Naugatuck", "New Haven", "North Branford", "North Haven",
         "Orange", "Oxford", "Prospect", "Seymour", "Southbury", "Wallingford",
         "Waterbury", "West Haven", "Wolcott", "Woodbridge"]  # New Haven County
FIELDS = ["OBJECTID", "Town_Name", "Parcel_ID", "Parcel_Type", "Unit_Type",
          "State_Use", "State_Use_Description", "Zone", "Land_Acres",
          "Assessed_Total", "Assessed_Land", "Assessed_Building",
          "Appraised_Building", "Valuation_Year", "AYB", "EYB", "Living_Area",
          "Occupancy", "Condition", "Model"]  # no owner or address fields
PAGE = 2000
OUT = pathlib.Path("data/parcels_raw")


def fetch(offset):
    params = {
        "where": "Town_Name IN (" + ",".join(f"'{t}'" for t in TOWNS) + ")",
        "outFields": ",".join(FIELDS),
        "outSR": 4326,               # longitude/latitude, like Overture
        "orderByFields": "OBJECTID",  # stable order for paging
        "resultOffset": offset,
        "resultRecordCount": PAGE,
        "f": "geojson",
    }
    url = BASE + "?" + urllib.parse.urlencode(params)
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                data = json.load(r)
            if "features" not in data:  # the server sent an error reply
                raise RuntimeError(str(data.get("error", data))[:200])
            return data
        except Exception as e:  # network hiccup or server error: wait and retry
            print(f"  retry {attempt + 1} at offset {offset}: {e}")
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"failed at offset {offset}")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    offset, total, start = 0, 0, time.time()
    while True:
        path = OUT / f"page_{offset // PAGE:04d}.geojson"
        if path.exists():
            n = len(json.loads(path.read_text())["features"])
        else:
            page = fetch(offset)
            n = len(page["features"])
            path.write_text(json.dumps(page))
        total += n
        if offset // PAGE % 10 == 0:
            print(f"{total:,} parcels, {time.time() - start:.0f} s")
        if n < PAGE:
            break
        offset += PAGE
    print(f"done: {total:,} parcels in {time.time() - start:.0f} s")


if __name__ == "__main__":
    main()
