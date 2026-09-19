"""Runs the shared 005-style and 007-style position/exit logic across several
timeframes in parallel against one tick stream, to compare how the dual-BB
breakout -> extension -> pullback -> countertrend signal performs at
different bar sizes.

005-style: 0.01 lot, SL=2R, whole-position lock to +0.25R at +0.5R, TP=+0.9R
           (from entry), no timeout.
007-style: 0.02 lot, SL=2R, lock to +0.25R at +0.5R, 50% partial at +1.0R,
           TP anchored to the signal bar's close +0.9R, 168h timeout.

Both use the same signal parameters as the live EAs: BB(20,2.0,Close) +
BB(4,4.0,Open), ExtensionR=0.95, PullbackR=0.10, 72h expiries.

`latency_seconds` (default 0) simulates real order-transmission delay: a
pullback-confirmation event is not acted on at the tick that fired it, but
held until a later tick at/after (event_time + latency_seconds), and the
entry is filled at THAT later tick's bid/ask -- i.e. whatever the market
has actually done during the delay, not the price at the moment the
condition was satisfied. This matters a lot here because the extension/
pullback reversal itself typically resolves within ~10-30 seconds
regardless of the nominal bar timeframe (measured separately), so a
few seconds of realistic execution latency consumes a large fraction of
the shorter timeframes' signal distance.
"""

from collections import deque

from .bars import BarBuilder
from .bbands import DualBB
from .signals import SignalTracker
from .strategies import PositionManager

TIMEFRAMES = [
    ('M1', 60), ('M2', 120), ('M3', 180), ('M5', 300),
    ('M10', 600), ('M15', 900), ('M30', 1800), ('H1', 3600),
]


def make_005style(tf_label):
    return PositionManager(f'005_{tf_label}', lots=0.01, stop_r=2.0, protect_trigger_r=0.5,
                            protect_r=0.25, tp_r=0.9, tp_relative='entry',
                            partial_trigger_r=None, timeout_hours=None)


def make_007style(tf_label):
    return PositionManager(f'007_{tf_label}', lots=0.02, stop_r=2.0, protect_trigger_r=0.5,
                            protect_r=0.25, tp_r=0.9, tp_relative='sig_close',
                            partial_trigger_r=1.0, partial_frac=0.5, timeout_hours=168)


class MultiTFRunner:
    def __init__(self, timeframes=TIMEFRAMES, latency_seconds=0):
        self.latency = latency_seconds
        self.tfs = []
        for label, secs in timeframes:
            self.tfs.append({
                'label': label,
                'secs': secs,
                'bars': BarBuilder(secs),
                'bb': DualBB(20, 2.0, 4, 4.0),
                'signals': SignalTracker(secs, 0.95, 0.10, 72, 72),
                's005': make_005style(label),
                's007': make_007style(label),
                'pending': deque(),  # (ready_ts, event)
            })
        self.trades = []
        self.n_ticks = 0

    def process_tick(self, ts, bid, ask):
        self.n_ticks += 1
        for tf in self.tfs:
            bar = tf['bars'].update(ts, bid)
            if bar is not None:
                bands = tf['bb'].on_bar_close(bar.o, bar.c)
                tf['signals'].on_bar_close(bar, bands)

            for ev in tf['signals'].on_tick(ts, bid, ask):
                if self.latency > 0:
                    tf['pending'].append((ts + self.latency, ev))
                else:
                    if tf['s005'].try_enter(ev, ts, bid, ask):
                        tf['s005'].manage(ts, bid, ask, self.trades)
                    if tf['s007'].try_enter(ev, ts, bid, ask):
                        tf['s007'].manage(ts, bid, ask, self.trades)

            if self.latency > 0:
                pending = tf['pending']
                while pending and pending[0][0] <= ts:
                    _, ev = pending.popleft()
                    if tf['s005'].try_enter(ev, ts, bid, ask):
                        tf['s005'].manage(ts, bid, ask, self.trades)
                    if tf['s007'].try_enter(ev, ts, bid, ask):
                        tf['s007'].manage(ts, bid, ask, self.trades)

            tf['s005'].manage(ts, bid, ask, self.trades)
            tf['s007'].manage(ts, bid, ask, self.trades)

    def process_array(self, ts_arr, bid_arr, ask_arr):
        proc = self.process_tick
        for ts, bid, ask in zip(ts_arr, bid_arr, ask_arr):
            proc(ts, bid, ask)
