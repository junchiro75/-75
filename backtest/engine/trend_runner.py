"""Runs the Donchian/ATR trend-breakout tracker across a few configs in
parallel against one tick stream."""

from .bars import BarBuilder
from .trend_strategy import TrendBreakoutTracker

CONFIGS = [
    ('H1_55_20', 3600, 55, 20),
    ('H4_20_10', 14400, 20, 10),
    ('H4_55_20', 14400, 55, 20),
    ('D1_20_10', 86400, 20, 10),
]


class TrendRunner:
    def __init__(self, configs=CONFIGS, stop_atr_mult=2.0, lots=0.01, allow_short=True):
        self.trackers = []
        for label, secs, n1, n2 in configs:
            self.trackers.append({
                'label': label,
                'secs': secs,
                'bars': BarBuilder(secs),
                'tracker': TrendBreakoutTracker(f'trend_{label}', secs, entry_n=n1, exit_n=n2,
                                                 stop_atr_mult=stop_atr_mult, lots=lots,
                                                 allow_short=allow_short),
            })
        self.trades = []
        self.n_ticks = 0

    def process_tick(self, ts, bid, ask):
        self.n_ticks += 1
        for t in self.trackers:
            bar = t['bars'].update(ts, bid)
            if bar is not None:
                t['tracker'].on_bar_close(bar.o, bar.h, bar.l, bar.c)
            t['tracker'].manage(ts, bid, ask, self.trades)

    def process_array(self, ts_arr, bid_arr, ask_arr):
        proc = self.process_tick
        for ts, bid, ask in zip(ts_arr, bid_arr, ask_arr):
            proc(ts, bid, ask)
