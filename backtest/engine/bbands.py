"""Dual Bollinger Band state, replicating MT5 iBands(SMA basis, population stddev).

Matches: iBands(_Symbol, TF, 20, 0, 2.0, PRICE_CLOSE) and
         iBands(_Symbol, TF, 4,  0, 4.0, PRICE_OPEN)
read at shift=1 (the just-closed bar), i.e. the window includes the bar
that just closed -- no future leak, but the bar's own O/C count toward its
own band.
"""

from collections import deque
import math


class _RollingBand:
    def __init__(self, n: int, k: float):
        self.n = n
        self.k = k
        self.buf = deque(maxlen=n)

    def push(self, price: float):
        self.buf.append(price)

    def ready(self) -> bool:
        return len(self.buf) == self.n

    def bands(self):
        n = self.n
        s = sum(self.buf)
        mean = s / n
        var = sum((p - mean) ** 2 for p in self.buf) / n  # population variance
        dev = math.sqrt(var)
        return mean + self.k * dev, mean - self.k * dev


class DualBB:
    """BB20 on Close and BB4 on Open, updated once per completed bar."""

    def __init__(self, n1=20, k1=2.0, n2=4, k2=4.0):
        self.bb_close = _RollingBand(n1, k1)
        self.bb_open = _RollingBand(n2, k2)

    def on_bar_close(self, bar_open: float, bar_close: float):
        """Push this bar's O/C, then return (upper20, lower20, upper4, lower4)
        computed over the window ending at (and including) this bar.
        Returns None if there isn't enough history yet.
        """
        self.bb_close.push(bar_close)
        self.bb_open.push(bar_open)
        if not (self.bb_close.ready() and self.bb_open.ready()):
            return None
        u20, l20 = self.bb_close.bands()
        u4, l4 = self.bb_open.bands()
        return u20, l20, u4, l4
