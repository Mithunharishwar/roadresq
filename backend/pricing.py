"""
Configurable pricing model for RoadResQ.

Produces the itemised breakdown the user must see *before* paying (spec §30):

    base service charge
  + distance / travel charge
  + additional service charge
  + taxes
  = total

Every rate comes from `config.Config`. These are configuration values for a
prototype — they are NOT claimed to be market-accurate, and nothing here
asserts a regulatory or commercial validity.
"""

from __future__ import annotations

from typing import Any, Dict, Optional

from config import Config


def _round_money(value: float) -> float:
    return round(float(value) + 1e-9, 2)


def quote(
    issue: str,
    distance_km: Optional[float] = None,
    *,
    extra_charge: float = 0.0,
    apply_tax: bool = True,
) -> Dict[str, Any]:
    """Build an itemised price quote.

    Args:
        issue: canonical service name (e.g. "Flat Tyre").
        distance_km: straight-line distance the assigned mechanic must travel.
            None is treated as 0 and reported as such rather than guessed.
        extra_charge: any additional on-site charge to add.
        apply_tax: include tax in the total.

    Returns:
        A dict with `lineItems` (each with label/amount), `subtotal`, `tax`,
        `total`, `currency`, and the `assumptions` that produced it.
    """
    base = float(Config.PRICING_BASE_FEE)

    km = 0.0
    if distance_km is not None:
        try:
            km = max(0.0, float(distance_km))
        except (TypeError, ValueError):
            km = 0.0

    travel = km * float(Config.PRICING_PER_KM)

    surcharge_key = None
    for name in Config.PRICING_SERVICE_SURCHARGE:
        if name.lower() == str(issue or "").strip().lower():
            surcharge_key = name
            break
    service_charge = float(
        Config.PRICING_SERVICE_SURCHARGE.get(surcharge_key, 0.0)
        if surcharge_key
        else 0.0
    )

    try:
        extra = max(0.0, float(extra_charge or 0.0))
    except (TypeError, ValueError):
        extra = 0.0

    line_items = [
        {
            "label": "Base service charge",
            "description": "Fixed call-out charge",
            "amount": _round_money(base),
        },
        {
            "label": "Distance / travel charge",
            "description": (
                f"{round(km, 2)} km x {Config.PRICING_PER_KM} per km "
                "(straight-line distance)"
            ),
            "amount": _round_money(travel),
        },
        {
            "label": "Service charge",
            "description": (
                f"{surcharge_key}" if surcharge_key else "No surcharge for this service"
            ),
            "amount": _round_money(service_charge),
        },
    ]

    if extra > 0:
        line_items.append(
            {
                "label": "Additional charge",
                "description": "On-site / parts adjustment",
                "amount": _round_money(extra),
            }
        )

    subtotal = _round_money(base + travel + service_charge + extra)
    tax = _round_money(subtotal * (Config.PRICING_TAX_PERCENT / 100.0)) if apply_tax else 0.0
    total = _round_money(subtotal + tax)

    return {
        "currency": Config.PRICING_CURRENCY,
        "lineItems": line_items,
        "subtotal": subtotal,
        "taxPercent": Config.PRICING_TAX_PERCENT if apply_tax else 0.0,
        "tax": tax,
        "total": total,
        # Amounts are integers in the smallest currency unit for the gateway.
        "totalMinorUnits": int(round(total * 100)),
        "assumptions": {
            "baseFee": base,
            "perKm": Config.PRICING_PER_KM,
            "taxPercent": Config.PRICING_TAX_PERCENT,
            "distanceKind": "great-circle (straight line)",
            "note": (
                "Prototype rate card. Configurable via environment variables; "
                "not verified against market rates."
            ),
        },
    }
