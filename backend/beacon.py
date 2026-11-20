"""
LAN presence beacon.

WHY THIS EXISTS
---------------
The Flutter app must find this server without being told an IP address. A
compiled-in or previously-saved address is only correct until the machine's
DHCP lease changes or the user joins a different Wi-Fi network — after which the
app retries a machine that no longer exists and prints

    SocketException: No route to host (OS Error: No route to host, errno = 113)

forever. That is the recurring "socket error" this feature removes.

Every two seconds this module broadcasts a small JSON datagram to UDP port 5051:

    {"service": "roadresq", "port": 5050, "host": "<machine>", "ts": 1730...}

`lib/services/backend_discovery.dart` listens on that port and adopts the
sender's address, so the phone follows the server across any address change
with no rebuild and no manual setting.

Datagrams are sent to the limited broadcast address and to the directed
broadcast address of each local subnet, because some access points pass one but
not the other. Failure to broadcast is never fatal: the client also falls back
to a bounded subnet sweep over TCP.
"""

from __future__ import annotations

import json
import logging
import socket
import threading
import time

log = logging.getLogger("roadresq.beacon")

BEACON_PORT = 5051
BEACON_INTERVAL_SECONDS = 2.0


def _local_addresses() -> list[str]:
    """IPv4 addresses of this machine, best effort."""
    addresses: list[str] = []
    try:
        _, _, ips = socket.gethostbyname_ex(socket.gethostname())
        addresses.extend(ip for ip in ips if not ip.startswith("127."))
    except OSError:
        pass
    # The address used for outbound traffic; also the one the phone can reach.
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("8.8.8.8", 80))
        primary = probe.getsockname()[0]
        if primary and not primary.startswith("127."):
            addresses.insert(0, primary)
    except OSError:
        pass
    finally:
        probe.close()

    unique: list[str] = []
    for ip in addresses:
        if ip not in unique and not ip.startswith("169.254."):
            unique.append(ip)
    return unique


def _broadcast_targets(addresses: list[str]) -> list[str]:
    """Limited broadcast plus each subnet's directed broadcast (best effort).

    The netmask is not available portably without extra dependencies, so the
    common LAN sizes are covered explicitly. A wrong guess is harmless: the
    datagram is dropped by the network.
    """
    targets = {"255.255.255.255"}
    for ip in addresses:
        parts = ip.split(".")
        if len(parts) != 4:
            continue
        a, b, c = parts[0], parts[1], parts[2]
        targets.add(f"{a}.{b}.{c}.255")  # /24
        third = int(c)
        targets.add(f"{a}.{b}.{third - third % 4 + 3}.255")  # /22 block
        targets.add(f"{a}.{b}.255.255")  # /16
    return sorted(targets)


def _run(port: int, interval: float, stop: threading.Event) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        while not stop.is_set():
            addresses = _local_addresses()
            payload = json.dumps(
                {
                    "service": "roadresq",
                    "port": port,
                    "host": socket.gethostname(),
                    "ts": int(time.time()),
                }
            ).encode("utf-8")
            for target in _broadcast_targets(addresses):
                try:
                    sock.sendto(payload, (target, BEACON_PORT))
                except OSError:
                    # A network that refuses broadcast is expected; the client
                    # sweeps instead. Only log once per target at debug level.
                    log.debug("beacon send to %s failed", target)
            stop.wait(interval)
    finally:
        sock.close()


class Beacon:
    """Owns the broadcasting thread's lifetime."""

    def __init__(self, port: int, interval: float = BEACON_INTERVAL_SECONDS):
        self.port = port
        self.interval = interval
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if self._thread is not None:
            return
        self._thread = threading.Thread(
            target=_run,
            args=(self.port, self.interval, self._stop),
            name="roadresq-beacon",
            daemon=True,
        )
        self._thread.start()
        log.info(
            "LAN beacon advertising port %s on udp/%s every %.0fs",
            self.port,
            BEACON_PORT,
            self.interval,
        )

    def stop(self) -> None:
        self._stop.set()
