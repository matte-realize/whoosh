#!/usr/bin/env python3
"""Import the City of Boston's Existing Bike Network (2024) into Whoosh's bike_facilities table.

Standard library only. Two inputs:
  * a saved snapshot (the default, works offline):  bike_network_mass_ave.json in this folder
  * --fetch: page through the live CKAN API (needs network), one street or the whole city

Outputs, all deterministic so diffs are reviewable:
  --sql PATH       upsert SQL (insert ... on conflict do update), safe to run more than once
  --fixture PATH   the website's fixture JSON (web/fixtures/bike_network.json)
  --save PATH      with --fetch, save the fetched records as a new snapshot

Examples:
  python3 import.py --sql ../../migrations/20261024170100_boston_bike_network_mass_ave.sql \\
                    --fixture ../../../web/fixtures/bike_network.json
  python3 import.py --fetch --save all_streets.json --sql /tmp/boston_bike_network.sql

Source: https://data.boston.gov/dataset/existing-bike-network-2024 (PDDL, public domain).
Each yearly edition is a separate dataset with its own record ids, so it gets its own source key.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_SNAPSHOT = HERE / "bike_network_mass_ave.json"
API = "https://data.boston.gov/api/3/action/datastore_search"
RESOURCE_ID = "e34b295e-1451-4e79-9e86-d9be609ffb34"
SOURCE_KEY = "boston_bike_network_2024"
SOURCE = {
    "key": SOURCE_KEY,
    "name": "Existing Bike Network (2024)",
    "publisher": "City of Boston, Boston Transportation Department",
    "url": "https://data.boston.gov/dataset/existing-bike-network-2024",
    "license": "Open Data Commons Public Domain Dedication and License (PDDL)",
    "notes": (
        "Inventory of existing bike facilities on City of Boston streets, for information only "
        "and not for trip routing; actual conditions may differ. Lists the current facility and "
        "its install year, not what was there before."
    ),
}
# Must match public.bike_facility_types in migration 20261024170000 (the fixture can't read it).
FACILITY_TYPES = {
    "BL": ("Bike lane", "painted"),
    "BFBL": ("Buffered bike lane", "painted"),
    "BLSL": ("Bike lane on one side, shared lane on the other side", "painted"),
    "CFBL": ("Contraflow bike lane", "painted"),
    "BL-PEAKBUS": ("Bike lane, bus lane at peak hours", "painted"),
    "SBL": ("Separated bike lane", "separated"),
    "CFSBL": ("Contraflow separated bike lane", "separated"),
    "SBLBL": ("Separated bike lane one side, bike lane on the other side", "partly_separated"),
    "SBLSL": ("Separated bike lane one side, shared lane on the other side", "partly_separated"),
    "SLM": ("Shared lane markings or shared bus lane", "shared"),
    "SLMTC": ("Shared lane markings on a traffic calmed street", "shared"),
    "CFBS": ("Contraflow bike street", "shared"),
    "PED": ("Pedestrianized street", "path"),
    "SUP": ("Shared use path", "path"),
    "SUPN": ("Natural surface shared use path", "path"),
    "SUPM": ("Minor shared use path", "path"),
    "WALK": ("Walkway", "path"),
}
BBOX = (42.22, 42.41, -71.20, -70.98)
MAX_POINTS = 10000


class SkipRecord(Exception):
    pass


def fetch(street: str | None) -> list[dict]:
    """Pages through the CKAN datastore API. Needs network access."""
    filters = {"STREET_NAM": street} if street else {}
    records: list[dict] = []
    offset = 0
    while True:
        query = urllib.parse.urlencode({
            "resource_id": RESOURCE_ID,
            "limit": 1000,
            "offset": offset,
            "filters": json.dumps(filters),
        })
        with urllib.request.urlopen(f"{API}?{query}", timeout=30) as response:
            payload = json.load(response)
        if not payload.get("success"):
            raise SystemExit("error: the API did not return success")
        batch = payload["result"]["records"]
        records.extend(batch)
        offset += len(batch)
        if not batch or offset >= payload["result"].get("total", offset):
            break
    return records


def parse_wkt(wkt: str) -> list[list[list[float]]]:
    """MULTILINESTRING [M] ((x y [m], ...), ...) -> list of parts of [lon, lat]. M values dropped."""
    if not re.match(r"^\s*(MULTI)?LINESTRING(\s+M)?\s*\(", wkt or ""):
        raise SkipRecord(f"unsupported geometry {wkt[:30]!r}")
    parts = []
    for body in re.findall(r"\(([^()]+)\)", wkt):
        points = []
        for pair in body.split(","):
            fields = pair.split()
            if len(fields) < 2:
                raise SkipRecord("bad coordinate")
            lon, lat = float(fields[0]), float(fields[1])
            if not (BBOX[0] <= lat <= BBOX[1] and BBOX[2] <= lon <= BBOX[3]):
                raise SkipRecord(f"coordinates outside Boston ({lat}, {lon})")
            points.append([round(lon, 6), round(lat, 6)])
        # Drop repeated points that rounding can create.
        deduped = [p for i, p in enumerate(points) if i == 0 or p != points[i - 1]]
        if len(deduped) >= 2:
            parts.append(deduped)
    if not parts:
        raise SkipRecord("no usable line")
    return parts


def clean(record: dict) -> list[dict]:
    """One source record -> one row per line part. Raises SkipRecord on anything unusable."""
    rid = (record.get("OID_") or "").strip()
    if not rid.isdigit():
        raise SkipRecord(f"missing OID_ ({record.get('_id')})")
    code = (record.get("ExisFacil") or "").strip()
    if code not in FACILITY_TYPES:
        raise SkipRecord(f"record {rid}: unknown facility code {code!r}")
    year_text = (record.get("InstallDat") or "").strip()
    install_year = int(year_text) if re.fullmatch(r"(19|20)\d\d", year_text) else None
    street = (record.get("STREET_NAM") or "").strip()[:120] or None
    parts = parse_wkt(record.get("shape_wkt") or "")
    rows = []
    for index, coordinates in enumerate(parts):
        if len(coordinates) > MAX_POINTS:
            raise SkipRecord(f"record {rid}: more than {MAX_POINTS} points")
        rows.append({
            # A multi-part line becomes rows "123", "123-2", "123-3", ...
            "source_record_id": rid if index == 0 else f"{rid}-{index + 1}",
            "street": street,
            "facility_code": code,
            "install_year": install_year,
            "route": {"type": "LineString", "coordinates": coordinates},
        })
    return rows


def q(value) -> str:
    if value is None:
        return "null"
    if isinstance(value, (int, float)):
        return repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def route_json(route: dict) -> str:
    return json.dumps(route, separators=(",", ":"))


def to_sql(rows: list[dict], retrieved_on: str, label: str) -> str:
    out = [
        f"-- GENERATED by supabase/data/boston-bike-network/import.py from {label}.",
        "-- Do not edit by hand; regenerate. Safe to run more than once (upserts).",
        f"-- {len(rows)} lane segments. Source: {SOURCE['url']} ({SOURCE['license']}).",
        "",
        "insert into public.data_sources (key, name, publisher, url, license, retrieved_on, data_through, notes)",
        "values (" + ", ".join(q(v) for v in [
            SOURCE["key"], SOURCE["name"], SOURCE["publisher"], SOURCE["url"], SOURCE["license"],
            retrieved_on, None, SOURCE["notes"],
        ]) + ")",
        "on conflict (key) do update set",
        "  name = excluded.name, publisher = excluded.publisher, url = excluded.url,",
        "  license = excluded.license, retrieved_on = excluded.retrieved_on,",
        "  data_through = excluded.data_through, notes = excluded.notes, updated_at = now();",
        "",
        "insert into public.bike_facilities (source, source_record_id, street, facility_code, install_year, route)",
        "values",
    ]
    out.append(",\n".join(
        "  (" + ", ".join([
            q(SOURCE_KEY), q(r["source_record_id"]), q(r["street"]), q(r["facility_code"]),
            q(r["install_year"]), q(route_json(r["route"])) + "::jsonb",
        ]) + ")"
        for r in rows
    ))
    out += [
        "on conflict (source, source_record_id) do update set",
        "  street = excluded.street, facility_code = excluded.facility_code,",
        "  install_year = excluded.install_year, route = excluded.route, imported_at = now();",
        "",
    ]
    return "\n".join(out)


def to_fixture(rows: list[dict], retrieved_on: str) -> dict:
    """The website's fixture: the same fields public_bike_facilities exposes."""
    return {
        "source": {k: SOURCE[k] for k in ("key", "name", "publisher", "url", "license")}
        | {"retrieved_on": retrieved_on, "data_through": None},
        "facilities": [
            {
                "source_record_id": r["source_record_id"],
                "street": r["street"],
                "facility_code": r["facility_code"],
                "facility_label": FACILITY_TYPES[r["facility_code"]][0],
                "protection": FACILITY_TYPES[r["facility_code"]][1],
                "install_year": r["install_year"],
                "route": r["route"],
            }
            for r in rows
        ],
    }


def sort_key(row: dict) -> tuple[int, int]:
    base, _, part = row["source_record_id"].partition("-")
    return int(base), int(part or 1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--snapshot", type=Path, default=DEFAULT_SNAPSHOT)
    parser.add_argument("--fetch", action="store_true", help="fetch from the live API instead of a snapshot")
    parser.add_argument("--street", default=None, help="with --fetch: exact name, e.g. 'Massachusetts Avenue'")
    parser.add_argument("--save", type=Path, help="with --fetch: write the fetched records as a snapshot")
    parser.add_argument("--sql", type=Path)
    parser.add_argument("--fixture", type=Path)
    args = parser.parse_args()

    if args.fetch:
        raw = fetch(args.street)
        retrieved_on = datetime.now(timezone.utc).date().isoformat()
        label = f"a live fetch on {retrieved_on} (street={args.street or 'all'})"
        if args.save:
            args.save.write_text(json.dumps({
                "source": SOURCE_KEY,
                **{k: SOURCE[k] for k in ("url", "license")},
                "resource_id": RESOURCE_ID,
                "query": {"STREET_NAM": args.street},
                "retrieved_on": retrieved_on,
                "records": raw,
            }, indent=2) + "\n")
    else:
        snapshot = json.loads(args.snapshot.read_text())
        raw = snapshot["records"]
        retrieved_on = snapshot["retrieved_on"]
        label = f"the snapshot {args.snapshot.name} (retrieved {retrieved_on})"

    rows, problems, seen = [], [], set()
    for record in raw:
        try:
            cleaned = clean(record)
        except (SkipRecord, ValueError) as error:
            problems.append(str(error))
            continue
        for row in cleaned:
            if row["source_record_id"] in seen:
                problems.append(f"record {row['source_record_id']}: duplicate")
                continue
            seen.add(row["source_record_id"])
            rows.append(row)
    rows.sort(key=sort_key)

    for problem in problems:
        print(f"skipped: {problem}", file=sys.stderr)
    print(f"{len(rows)} segments ready, {len(problems)} skipped", file=sys.stderr)

    if args.sql:
        args.sql.write_text(to_sql(rows, retrieved_on, label))
    if args.fixture:
        args.fixture.write_text(json.dumps(to_fixture(rows, retrieved_on), indent=2) + "\n")
    return 0 if rows else 1


if __name__ == "__main__":
    raise SystemExit(main())
