"""Runs the SYMMETRIC fast-confirm idea (both bear->BUY and bull->SELL
get a next-bar-confirmation fast path, plus the original mechanical
extension/pullback fallback in both directions) for 005-style (M2) and
007-style (M10) exit economics, full period."""

from .bars import BarBuilder
from .bbands import DualBB
from .symfastconfirm_signals import SymmetricFastConfirmSignalTracker
from .strategies import PositionManager


class SymFastConfirmRunner:
    def __init__(self):
        self.m10_bars = BarBuilder(600)
        self.m2_bars = BarBuilder(120)
        self.m10_bb = DualBB(20, 2.0, 4, 4.0)
        self.m2_bb = DualBB(20, 2.0, 4, 4.0)
        self.m10_signals = SymmetricFastConfirmSignalTracker(600, 0.95, 0.10, 72, 72)
        self.m2_signals = SymmetricFastConfirmSignalTracker(120, 0.95, 0.10, 72, 72)

        self.s005 = PositionManager('005_symfastconfirm', lots=0.01, stop_r=2.0, protect_trigger_r=0.5,
                                     protect_r=0.25, tp_r=0.9, tp_relative='entry',
                                     partial_trigger_r=None, timeout_hours=None)
        self.s007 = PositionManager('007_symfastconfirm', lots=0.02, stop_r=2.0, protect_trigger_r=0.5,
                                     protect_r=0.25, tp_r=0.9, tp_relative='sig_close',
                                     partial_trigger_r=1.0, partial_frac=0.5, timeout_hours=168)
        self.trades = []
        self.n_ticks = 0

    def process_tick(self, ts, bid, ask):
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
            if self.s007.try_enter(ev, ts, bid, ask):
                self.s007.manage(ts, bid, ask, self.trades)
        for ev in self.m2_signals.on_tick(ts, bid, ask):
            if self.s005.try_enter(ev, ts, bid, ask):
                self.s005.manage(ts, bid, ask, self.trades)

        self.s005.manage(ts, bid, ask, self.trades)
        self.s007.manage(ts, bid, ask, self.trades)

    def process_array(self, ts_arr, bid_arr, ask_arr):
        proc = self.process_tick
        for ts, bid, ask in zip(ts_arr, bid_arr, ask_arr):
            proc(ts, bid, ask)
