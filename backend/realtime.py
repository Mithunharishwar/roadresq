"""
Realtime event hub.

The Flask-SocketIO instance lives in `roadresq_backend.py`. Route modules in the
`api_v2` blueprint need to broadcast from HTTP handlers without importing the
application module (which would create a circular import). They call
`emit_event()` here instead; `roadresq_backend.py` registers the live socket
object once at startup.

If no socket is registered the call is a no-op and is logged, so HTTP endpoints
keep working when the server runs without realtime enabled.

Spec references: §22 (live tracking), §23 (real-time synchronisation).
"""

from __future__ import annotations

import logging
from typing import Any, Dict, Optional

log = logging.getLogger("roadresq.realtime")

_socketio = None


def register(socketio_instance) -> None:
    """Called once by the application module after SocketIO is created."""
    global _socketio
    _socketio = socketio_instance


def is_available() -> bool:
    return _socketio is not None


def emit_event(event: str, payload: Dict[str, Any], room: Optional[str] = None) -> bool:
    """Broadcast `payload` under `event`. Returns True when actually emitted."""
    if _socketio is None:
        log.debug("SocketIO not registered; dropped event '%s'", event)
        return False
    try:
        if room:
            _socketio.emit(event, payload, to=room)
        else:
            # With neither `to` nor `room`, Flask-SocketIO 5.x already
            # broadcasts to every client. Passing the legacy `broadcast=True`
            # keyword raises TypeError on this version, which previously made
            # every realtime update silently fail.
            _socketio.emit(event, payload)
        return True
    except Exception as exc:  # pragma: no cover - transport level failure
        log.warning("Failed to emit '%s': %s", event, exc)
        return False
