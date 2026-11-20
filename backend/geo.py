"""
Geospatial helpers for RoadResQ.

Pure functions only: no Flask, no database. This keeps the geometry used by the
allocation engine independently testable.

Spec references: §16 (regional hub system), §17 (region compatibility),
§20 (invalid coordinate handling), §38 (validate GPS coordinates).
"""

from __future__ import annotations

import math
from typing import Any, Dict, Iterable, Optional, Tuple

EARTH_RADIUS_KM = 6371.0088

# Plausible coordinate bounds. Anything outside is rejected rather than
# silently treated as (0, 0) — the old backend defaulted missing lat/lng to 0,
# which places every request in the Gulf of Guinea.
LAT_MIN, LAT_MAX = -90.0, 90.0
LNG_MIN, LNG_MAX = -180.0, 180.0


def is_valid_coordinate(lat: Any, lng: Any) -> bool:
    """True when both values are finite numbers inside valid lat/lng bounds."""
    try:
        lat_f = float(lat)
        lng_f = float(lng)
    except (TypeError, ValueError):
        return False

    if math.isnan(lat_f) or math.isnan(lng_f):
        return False
    if math.isinf(lat_f) or math.isinf(lng_f):
        return False

    return (
        LAT_MIN <= lat_f <= LAT_MAX and LNG_MIN <= lng_f <= LNG_MAX
    )


def coerce_coordinate(lat: Any, lng: Any) -> Optional[Tuple[float, float]]:
    """Return (lat, lng) as floats, or None when the pair is not usable."""
    if not is_valid_coordinate(lat, lng):
        return None
    return float(lat), float(lng)


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance in kilometres.

    This is straight-line ("as the crow flies") distance, not road distance.
    All distances reported by this backend are of this kind and are described
    as such — no road-network optimisation is claimed. §22
    """
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lng2 - lng1)

    a = (
        math.sin(d_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2.0) ** 2
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))
    return EARTH_RADIUS_KM * c


def distance_meters(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Straight-line distance in metres."""
    return haversine_km(lat1, lng1, lat2, lng2) * 1000.0


def estimate_eta_minutes(distance_km: float, avg_speed_kmh: float) -> float:
    """ETA from straight-line distance and an assumed average speed.

    The assumed speed is configuration, not a measurement. Reported ETAs are
    therefore labelled as estimates. §22
    """
    if avg_speed_kmh <= 0:
        return 0.0
    return round((distance_km / avg_speed_kmh) * 60.0, 1)


def bbox_contains(bbox: Dict[str, Any], lat: float, lng: float) -> bool:
    """True when (lat, lng) lies inside an axis-aligned bounding box.

    Accepts either {latMin, latMax, lngMin, lngMax} or {minLat, maxLat,
    minLng, maxLng} key styles so both the legacy zone documents and the new
    region documents resolve.
    """
    if not isinstance(bbox, dict):
        return False

    def pick(*names):
        for n in names:
            if bbox.get(n) is not None:
                try:
                    return float(bbox[n])
                except (TypeError, ValueError):
                    continue
        return None

    lat_min = pick("latMin", "minLat")
    lat_max = pick("latMax", "maxLat")
    lng_min = pick("lngMin", "minLng")
    lng_max = pick("lngMax", "maxLng")

    if None in (lat_min, lat_max, lng_min, lng_max):
        return False

    return (lat_min <= lat <= lat_max) and (lng_min <= lng <= lng_max)


def _point_in_ring(ring: Iterable[Iterable[float]], lat: float, lng: float) -> bool:
    """Ray-casting point-in-polygon. Ring points are [lng, lat] (GeoJSON)."""
    points = [(float(p[0]), float(p[1])) for p in ring if len(p) >= 2]
    if len(points) < 3:
        return False

    inside = False
    n = len(points)
    j = n - 1
    for i in range(n):
        xi, yi = points[i]
        xj, yj = points[j]
        intersects = ((yi > lat) != (yj > lat)) and (
            lng < (xj - xi) * (lat - yi) / ((yj - yi) or 1e-12) + xi
        )
        if intersects:
            inside = not inside
        j = i
    return inside


def polygon_contains(polygon: Dict[str, Any], lat: float, lng: float) -> bool:
    """GeoJSON-Polygon containment. Supports Polygon and MultiPolygon."""
    if not isinstance(polygon, dict):
        return False

    ptype = polygon.get("type")
    coords = polygon.get("coordinates")
    if not coords:
        return False

    try:
        if ptype == "Polygon":
            # coordinates: [ exteriorRing, holeRing, ... ]
            if not _point_in_ring(coords[0], lat, lng):
                return False
            for hole in coords[1:]:
                if _point_in_ring(hole, lat, lng):
                    return False
            return True

        if ptype == "MultiPolygon":
            for poly in coords:
                if not poly:
                    continue
                if _point_in_ring(poly[0], lat, lng):
                    in_hole = any(_point_in_ring(h, lat, lng) for h in poly[1:])
                    if not in_hole:
                        return True
            return False
    except (TypeError, ValueError, IndexError):
        return False

    return False


def region_contains(region: Dict[str, Any], lat: float, lng: float) -> bool:
    """True when (lat, lng) falls inside a region document.

    A region may be described by a GeoJSON `boundary` polygon, by a
    `bbox`/flat min-max box, or (fallback) by a `center` + `radiusKm` circle.
    """
    if not isinstance(region, dict):
        return False

    boundary = region.get("boundary")
    if isinstance(boundary, dict) and boundary.get("type") in (
        "Polygon",
        "MultiPolygon",
    ):
        return polygon_contains(boundary, lat, lng)

    bbox = region.get("bbox") or region
    if bbox_contains(bbox, lat, lng):
        return True

    center = region.get("center") or {}
    radius = region.get("radiusKm") or region.get("radius_km")
    if isinstance(center, dict) and radius:
        # coerce_coordinate returns None (not a tuple) for an unusable pair, so
        # it must not be unpacked directly.
        center_coords = coerce_coordinate(center.get("lat"), center.get("lng"))
        if center_coords is None:
            return False
        c_lat, c_lng = center_coords
        try:
            return haversine_km(c_lat, c_lng, lat, lng) <= float(radius)
        except (TypeError, ValueError):
            return False

    return False


def resolve_region(
    regions: Iterable[Dict[str, Any]], lat: float, lng: float
) -> Optional[Dict[str, Any]]:
    """Return the smallest (most specific) region containing the point.

    When regions overlap, the one with the smallest stated `radiusKm` wins,
    falling back to insertion order. Returns None when the point is outside
    every region — callers must handle that explicitly rather than guessing.
    """
    matches = [r for r in regions if region_contains(r, lat, lng)]
    if not matches:
        return None

    def area_key(region: Dict[str, Any]):
        radius = region.get("radiusKm") or region.get("radius_km")
        try:
            return float(radius) if radius is not None else float("inf")
        except (TypeError, ValueError):
            return float("inf")

    matches.sort(key=area_key)
    return matches[0]
