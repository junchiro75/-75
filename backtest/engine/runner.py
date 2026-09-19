"""Ties bars + dual-BB + signal tracking + per-strategy position managers
together into one tick-driven backtest, replaying 004/005/007 in parallel
against a single XAUUSD+ tick stream.

Feed ticks in chronological order via process_tick(); state (open positions,
pending setups, rolling BB history, in-progress bars) persists across calls,
so multiple monthly files can be streamed through the same instance without
losing continuity at month boundaries.
"""

from .bars import BarBuilder
from .bbands import DualBB
from .signals import SignalTracker
from .strategies import make_004, make_005, make_007


class BacktestRunner:
    def __init__(self):
        self.m10_bars = BarBuilder(600)
        self.m2_bars = BarBuilder(120)
        self.m10_bb = DualBB(20, 2.0, 4, 4.0)
        self.m2_bb = DualBB(20, 2.0, 4, 4.0)
        self.m10_signals = SignalTracker(600, 0.95, 0.10, 72, 72)
        self.m2_signals = SignalTracker(120, 0.95, 0.10, 72, 72)

        self.s004 = make_004()
        self.s005 = make_005()
        self.s007 = make_007()

        self.trades = []
        self.n_ticks = 0

    def process_tick(self, ts: int, bid: float, ask: float):
        self.n_ticks += 1

        bar10 = self.m10_bars.update(ts, bid)
        if bar10 is not None:
            bands = self.m10_bb.on_bar_close(bar10.o, bar10.c)
            self.m10_signals.on_bar_close(bar10, bands)

        bar2 = self.m2_bars.update(ts, bid)
        if bar2 is not None:
            bands2 = self.m2_bb.on_bar_close(bar2.o, bar2.c)
            self.m2_signals.on_bar_close(bar2, bands2)

        for ev in self.m10_signals.on_tick(ts, bid, ask):
            if self.s004.try_enter(ev, ts, bid, ask):
                self.s004.manage(ts, bid, ask, self.trades)
            if self.s007.try_enter(ev, ts, bid, ask):
                self.s007.manage(ts, bid, ask, self.trades)

        for ev in self.m2_signals.on_tick(ts, bid, ask):
            if self.s005.try_enter(ev, ts, bid, ask):
                self.s005.manage(ts, bid, ask, self.trades)

        self.s004.manage(ts, bid, ask, self.trades)
        self.s005.manage(ts, bid, ask, self.trades)
        self.s007.manage(ts, bid, ask, self.trades)

    def process_array(self, ts_arr, bid_arr, ask_arr):
        """Fast path: iterate parallel numpy/py arrays of equal length."""
        proc = self.process_tick
        for ts, bid, ask in zip(ts_arr, bid_arr, ask_arr):
            proc(ts, bid, ask)
