"""Tick -> OHLC bar aggregation, matching MT5's Bid-based chart construction."""

from dataclasses import dataclass


@dataclass
class Bar:
    start: int  # epoch seconds, aligned to period boundary
    o: float
    h: float
    l: float
    c: float


class BarBuilder:
    """Builds fixed-period OHLC bars from a stream of (epoch_seconds, bid) ticks.

    Bar boundaries are aligned to clock time (e.g. M10 bars start at :00, :10, ...),
    matching how MT5 timeframes are anchored, since Unix epoch 0 falls on every
    such boundary already.
    """

    def __init__(self, period_seconds: int):
        self.period = period_seconds
        self._cur_start = None
        self._o = self._h = self._l = self._c = None

    def update(self, ts: int, bid: float):
        """Feed one tick. Returns a completed Bar when a bar just closed, else None."""
        bucket = (ts // self.period) * self.period
        if self._cur_start is None:
            self._cur_start = bucket
            self._o = self._h = self._l = self._c = bid
            return None
        if bucket == self._cur_start:
            if bid > self._h:
                self._h = bid
            if bid < self._l:
                self._l = bid
            self._c = bid
            return None

        # New bucket -> the previous bar is complete.
        completed = Bar(self._cur_start, self._o, self._h, self._l, self._c)
        self._cur_start = bucket
        self._o = self._h = self._l = self._c = bid
        return completed
