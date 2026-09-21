"""In-process request metrics.

A tiny thread-safe counter that the `/api/health` endpoint surfaces. For
production deployments swap this for Prometheus or hosted metrics — the
interface intentionally matches `Histogram.observe()` so the swap is a
one-line change.
"""

from __future__ import annotations

import threading
from collections import defaultdict
from typing import Any


class RequestMetrics:
    """Aggregate counters + average latency, partitioned by route + status."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._counts: dict[tuple[str, int], int] = defaultdict(int)
        self._latency_sum_ms: dict[tuple[str, int], float] = defaultdict(float)
        self._latency_min_ms: dict[tuple[str, int], float] = {}
        self._latency_max_ms: dict[tuple[str, int], float] = {}
        self._severity_predictions: dict[str, int] = defaultdict(int)

    def record(self, *, path: str, status: int, latency_ms: float) -> None:
        key = (path, status)
        with self._lock:
            self._counts[key] += 1
            self._latency_sum_ms[key] += latency_ms
            current_min = self._latency_min_ms.get(key)
            self._latency_min_ms[key] = (
                latency_ms if current_min is None else min(current_min, latency_ms)
            )
            current_max = self._latency_max_ms.get(key)
            self._latency_max_ms[key] = (
                latency_ms if current_max is None else max(current_max, latency_ms)
            )

    def record_prediction(self, severity: str) -> None:
        with self._lock:
            self._severity_predictions[severity] += 1

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            routes: dict[str, dict[str, Any]] = {}
            for (path, status), count in self._counts.items():
                bucket = routes.setdefault(path, {"by_status": {}})
                avg_latency = self._latency_sum_ms[(path, status)] / count
                bucket["by_status"][str(status)] = {
                    "count": count,
                    "avg_latency_ms": round(avg_latency, 2),
                    "min_latency_ms": round(
                        self._latency_min_ms[(path, status)], 2
                    ),
                    "max_latency_ms": round(
                        self._latency_max_ms[(path, status)], 2
                    ),
                }
            total = sum(self._counts.values())
            errors = sum(c for (_, status), c in self._counts.items() if status >= 400)
            return {
                "total": total,
                "errors": errors,
                "error_rate": round(errors / total, 4) if total else 0.0,
                "by_route": routes,
                "predictions_by_severity": dict(self._severity_predictions),
            }
