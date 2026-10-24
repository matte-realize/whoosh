#!/usr/bin/env python3
"""Import the City of Boston's Streets Hourly Bike Counts into Whoosh's bike count tables.

Standard library only. The source is hourly and per direction; this importer keeps one row per
counter per local day (both directions summed), which is what the website and the views use.

Two inputs:
  * a saved snapshot (the default, works offline):  bike_counts_mass_ave.json in this folder.
    It holds the daily sums as returned by the city's own SQL API (the query is saved with it).
  * --fetch: run the same query on the live API (needs network) for any location-name pattern

Outputs, all deterministic so diffs are reviewable:
  --sql PATH       upsert SQL, safe to run more than once
  --fixture PATH   the website's fixture JSON (web/fixtures/bike_counts.json), with the same
                   numbers the public_bike_count_years and public_bike_count_locations views return
  --save PATH      with --fetch, save the fetched rows as a new snapshot

Examples:
  python3 import.py --sql ../../migrations/20261024170200_boston_bike_counts_mass_ave.sql \\
                    --fixture ../../../web/fixtures/bike_counts.json
  python3 import.py --fetch --location-like '%' --save all_counters.json --sql /tmp/counts.sql

Source: https://data.boston.gov/dataset/streets-hourly-bike-counts (PDDL, public domain).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import date, datetime, timezone
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_SNAPSHOT = HERE / "bike_counts_mass_ave.json"
API_SQL = "https://data.boston.gov/api/3/action/datastore_search_sql"
RESOURCE_ID = "c97f6d9a-aee1-4f95-aea1-a47b74608506"
SOURCE_KEY = "boston_bike_counts"
SOURCE = {
    "key": SOURCE_KEY,
    "name": "Streets Hourly Bike Counts",
    "publisher": "City of Boston, Boston Transportation Department",
    "url": "https://data.boston.gov/dataset/streets-hourly-bike-counts",
    "license": "Open Data Commons Public Domain Dedication and License (PDDL)",
    "notes": (
        "Automated counts at about 90 city locations a few times a year. Imported as one row per "
        "counter per local day, both directions summed. A yearly figure averages the full days "
        "counted that year, usually 2 to 8."
    ),
}
BBOX = (42.22, 42.41, -71.20, -70.98)


class SkipRecord(Exception):
    pass


def daily_sql(location_like: str) -> str:
    pattern = location_like.replace("'", "''")
    return (
        "SELECT count_id, location_name, lat, long, date, count(distinct time) AS hours, "
        "sum(bike::numeric) AS bikes, sum(mv_total::numeric) AS motor_vehicles "
        f'FROM "{RESOURCE_ID}" WHERE location_name ILIKE \'{pattern}\' '
        "GROUP BY 1,2,3,4,5 ORDER BY 1,5"
    )


def fetch(location_like: str) -> tuple[str, list[dict]]:
    """Runs the daily-sum query on the city's API. Needs network access."""
    sql = daily_sql(location_like)
    with urllib.request.urlopen(f"{API_SQL}?{urllib.parse.urlencode({'sql': sql})}", timeout=60) as response:
        payload = json.load(response)
    if not payload.get("success"):
        raise SystemExit("error: the API did not return success")
    return sql, payload["result"]["records"]


def parse_day(text: str) -> date:
    # "6/11/2025 4:00:00.000": local midnight written in UTC; the calendar part is the local day.
    match = re.match(r"^(\d{1,2})/(\d{1,2})/(\d{4})\b", text or "")
    if not match:
        raise SkipRecord(f"bad date {text!r}")
    month, day, year = (int(g) for g in match.groups())
    return date(year, month, day)


def whole(value) -> int | None:
    if value is None or value == "":
        return None
    number = Decimal(str(value))
    if number != number.to_integral_value() or number < 0:
        raise SkipRecord(f"bad count {value!r}")
    return int(number)


def clean(record: dict) -> tuple[dict, dict]:
    location_id = str(record.get("count_id") or "").strip()
    name = (record.get("location_name") or "").strip()[:120]
    if not location_id or not name:
        raise SkipRecord("missing count_id or location_name")
    lat, lon = float(record["lat"]), float(record["long"])
    if not (BBOX[0] <= lat <= BBOX[1] and BBOX[2] <= lon <= BBOX[3]):
        raise SkipRecord(f"{name}: coordinates outside Boston ({lat}, {lon})")
    hours = int(record["hours"])
    if not 1 <= hours <= 24:
        raise SkipRecord(f"{name}: {hours} hours in one day")
    bikes = whole(record["bikes"])
    if bikes is None or bikes > 100000:
        raise SkipRecord(f"{name}: bad bike count {record['bikes']!r}")
    location = {"location_id": location_id, "name": name, "latitude": round(lat, 6), "longitude": round(lon, 6)}
    day = {
        "location_id": location_id,
        "count_date": parse_day(record["date"]).isoformat(),
        "hours_counted": hours,
        "bikes": bikes,
        "motor_vehicles": whole(record.get("motor_vehicles")),
    }
    return location, day


def half_up(value: Decimal, places: str = "1") -> Decimal:
    """Postgres round() on numeric rounds halves away from zero; Python's round() does not."""
    return value.quantize(Decimal(places), rounding=ROUND_HALF_UP)


def year_rows(days: list[dict]) -> list[dict]:
    """The same numbers as the public_bike_count_years view: full days only."""
    groups: dict[tuple[str, int], list[dict]] = defaultdict(list)
    for d in days:
        if d["hours_counted"] == 24:
            groups[(d["location_id"], int(d["count_date"][:4]))].append(d)
    rows = []
    for (location_id, year), group in sorted(groups.items(), key=lambda item: (sort_id(item[0][0]), item[0][1])):
        bikes = [d["bikes"] for d in group]
        mvs = [d["motor_vehicles"] for d in group if d["motor_vehicles"] is not None]
        rows.append({
            "location_id": location_id,
            "year": year,
            "days_counted": len(group),
            "avg_daily_bikes": int(half_up(Decimal(sum(bikes)) / len(bikes))),
            "min_daily_bikes": min(bikes),
            "max_daily_bikes": max(bikes),
            "avg_daily_motor_vehicles": int(half_up(Decimal(sum(mvs)) / len(mvs))) if mvs else None,
        })
    return rows


def location_rows(locations: dict[str, dict], years: list[dict]) -> list[dict]:
    """The same numbers as the public_bike_count_locations view."""
    rows = []
    for location_id in sorted(locations, key=sort_id):
        mine = [y for y in years if y["location_id"] == location_id]
        if not mine:
            continue  # no full day counted: the view leaves it out too
        latest = max(mine, key=lambda y: y["year"])
        bikes, mv = latest["avg_daily_bikes"], latest["avg_daily_motor_vehicles"]
        total = bikes + (mv or 0)
        rows.append({
            **locations[location_id],
            "days_counted": sum(y["days_counted"] for y in mine),
            "first_year": min(y["year"] for y in mine),
            "last_year": latest["year"],
            "latest_year_days": latest["days_counted"],
            "latest_avg_daily_bikes": bikes,
            "latest_avg_daily_motor_vehicles": mv,
            "latest_bike_share": float(half_up(Decimal(bikes) / total, "0.001")) if total else None,
        })
    return rows


def sort_id(location_id: str) -> tuple[int, str]:
    return (int(location_id), "") if location_id.isdigit() else (sys.maxsize, location_id)


def q(value) -> str:
    if value is None:
        return "null"
    if isinstance(value, (int, float)):
        return repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def to_sql(locations: dict[str, dict], days: list[dict], retrieved_on: str, data_through: str, label: str) -> str:
    out = [
        f"-- GENERATED by supabase/data/boston-bike-counts/import.py from {label}.",
        "-- Do not edit by hand; regenerate. Safe to run more than once (upserts).",
        f"-- {len(locations)} counters, {len(days)} counted days. Source: {SOURCE['url']} ({SOURCE['license']}).",
        "",
        "insert into public.data_sources (key, name, publisher, url, license, retrieved_on, data_through, notes)",
        "values (" + ", ".join(q(v) for v in [
            SOURCE["key"], SOURCE["name"], SOURCE["publisher"], SOURCE["url"], SOURCE["license"],
            retrieved_on, data_through, SOURCE["notes"],
        ]) + ")",
        "on conflict (key) do update set",
        "  name = excluded.name, publisher = excluded.publisher, url = excluded.url,",
        "  license = excluded.license, retrieved_on = excluded.retrieved_on,",
        "  data_through = excluded.data_through, notes = excluded.notes, updated_at = now();",
        "",
        "insert into public.bike_count_locations (source, location_id, name, latitude, longitude)",
        "values",
        ",\n".join(
            "  (" + ", ".join(q(v) for v in [SOURCE_KEY, l["location_id"], l["name"], l["latitude"], l["longitude"]]) + ")"
            for l in (locations[k] for k in sorted(locations, key=sort_id))
        ),
        "on conflict (source, location_id) do update set",
        "  name = excluded.name, latitude = excluded.latitude, longitude = excluded.longitude, updated_at = now();",
        "",
        "insert into public.bike_count_days (source, location_id, count_date, hours_counted, bikes, motor_vehicles)",
        "values",
        ",\n".join(
            "  (" + ", ".join(q(v) for v in [
                SOURCE_KEY, d["location_id"], d["count_date"], d["hours_counted"], d["bikes"], d["motor_vehicles"],
            ]) + ")"
            for d in days
        ),
        "on conflict (source, location_id, count_date) do update set",
        "  hours_counted = excluded.hours_counted, bikes = excluded.bikes,",
        "  motor_vehicles = excluded.motor_vehicles, imported_at = now();",
        "",
    ]
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--snapshot", type=Path, default=DEFAULT_SNAPSHOT)
    parser.add_argument("--fetch", action="store_true", help="query the live API instead of a snapshot")
    parser.add_argument("--location-like", default="Massachusetts Avenue%",
                        help="with --fetch: SQL ILIKE pattern on location_name ('%%' for all)")
    parser.add_argument("--save", type=Path, help="with --fetch: write the fetched rows as a snapshot")
    parser.add_argument("--sql", type=Path)
    parser.add_argument("--fixture", type=Path)
    args = parser.parse_args()

    if args.fetch:
        query_sql, raw = fetch(args.location_like)
        retrieved_on = datetime.now(timezone.utc).date().isoformat()
        label = f"a live fetch on {retrieved_on} (location_name ILIKE {args.location_like!r})"
        if args.save:
            args.save.write_text(json.dumps({
                "source": SOURCE_KEY,
                **{k: SOURCE[k] for k in ("url", "license")},
                "resource_id": RESOURCE_ID,
                "query_sql": query_sql,
                "retrieved_on": retrieved_on,
                "records": raw,
            }, indent=2) + "\n")
    else:
        snapshot = json.loads(args.snapshot.read_text())
        raw = snapshot["records"]
        retrieved_on = snapshot["retrieved_on"]
        label = f"the snapshot {args.snapshot.name} (retrieved {retrieved_on})"

    locations: dict[str, dict] = {}
    days: list[dict] = []
    problems: list[str] = []
    seen: set[tuple[str, str]] = set()
    for record in raw:
        try:
            location, day = clean(record)
        except (SkipRecord, KeyError, ValueError) as error:
            problems.append(str(error))
            continue
        known = locations.setdefault(location["location_id"], location)
        if known != location:
            problems.append(f"counter {location['location_id']}: name or position differs between rows; kept the first")
        key = (day["location_id"], day["count_date"])
        if key in seen:
            problems.append(f"counter {key[0]} on {key[1]}: duplicate day")
            continue
        seen.add(key)
        days.append(day)
    days.sort(key=lambda d: (sort_id(d["location_id"]), d["count_date"]))

    for problem in problems:
        print(f"skipped: {problem}", file=sys.stderr)
    print(f"{len(locations)} counters, {len(days)} days ready, {len(problems)} skipped", file=sys.stderr)
    if not days:
        return 1

    # The last counted day is the honest "data through" for this snapshot.
    data_through = max(d["count_date"] for d in days)

    if args.sql:
        args.sql.write_text(to_sql(locations, days, retrieved_on, data_through, label))
    if args.fixture:
        years = year_rows(days)
        args.fixture.write_text(json.dumps({
            "source": {k: SOURCE[k] for k in ("key", "name", "publisher", "url", "license")}
            | {"retrieved_on": retrieved_on, "data_through": data_through},
            "locations": location_rows(locations, years),
            "years": years,
        }, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
