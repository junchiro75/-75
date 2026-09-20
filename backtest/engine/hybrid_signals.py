"""Hybrid signal tracker for the "always end up BUY" idea:

- BEAR breakout (would normally lead to a countertrend BUY after
  +0.95R extension and -0.10R pullback): unchanged from the original
  EAs -- wait for extension then pullback, then enter BUY.
- BULL breakout (would normally lead to a countertrend SELL after the
  same extension/pullback wait, now disabled by AllowShort=false):
  instead of waiting at all, enter BUY immediately (trend-following
  the bull breakout) as soon as the signal bar closes.

This reuses BarBuilder/DualBB for bar/indicator construction and the
existing SignalTracker for the bear-side extension/pullback logic, but
intercepts bull signals before they ever reach the extension tracking.
"""

from .signals import SignalTracker, TriggerEvent


class HybridSignalTracker:
    def __init__(self, period_seconds, extension_r=0.95, pullback_r=0.10,
                 max_extension_hours=72, max_pullback_hours=72):
        # Only ever receives BEAR signals (sigdir=-1) -> its emitted
        # TriggerEvents (dir=+1, i.e. BUY) are unchanged from the original.
        self._bear_tracker = SignalTracker(period_seconds, extension_r, pullback_r,
                                            max_extension_hours, max_pullback_hours)
        self.pending_immediate = []  # bull-breakout bars awaiting their first post-close tick

    def on_bar_close(self, bar, bands):
        if bands is None:
            return
        u20, l20, u4, l4 = bands
        o, h, l, c = bar.o, bar.h, bar.l, bar.c
        bull = c > o and h >= u20 and h >= u4
        bear = c < o and l <= l20 and l <= l4
        if bear:
            self._bear_tracker.on_bar_close(bar, bands)
        elif bull:
            R = abs(c - o)
            if R > 0:
                self.pending_immediate.append({'R': R, 'sig_close': c})

    def on_tick(self, ts, bid, ask):
        events = self._bear_tracker.on_tick(ts, bid, ask)
        if self.pending_immediate:
            for setup in self.pending_immediate:
                events.append(TriggerEvent(time=ts, dir=1, R=setup['R'], sig_close=setup['sig_close']))
            self.pending_immediate = []
        return events
