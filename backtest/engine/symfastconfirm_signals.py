"""Symmetric next-bar-confirmation signal tracker.

Extends the fast-confirm idea (bear signal bar -> if next bar is
bullish, BUY immediately) to BOTH directions:

- BEAR breakout bar: fast path (next bar bullish -> immediate BUY) +
  the original extension(0.95R)+pullback(0.10R) fallback -> BUY.
- BULL breakout bar (previously skipped under AllowShort=false): the
  SAME treatment mirrored -- fast path (next bar bearish -> immediate
  SELL) + the original extension/pullback fallback -> SELL.

This reintroduces SELL trades (both the new fast-confirm ones and the
old mechanical ones), unlike FastConfirmSignalTracker which keeps bull
breakouts disabled. Whichever path (fast or mechanical) fires first
wins; PositionManager ignores the other once a position is open.
"""

from .signals import SignalTracker, TriggerEvent


class SymmetricFastConfirmSignalTracker:
    def __init__(self, period_seconds, extension_r=0.95, pullback_r=0.10,
                 max_extension_hours=72, max_pullback_hours=72):
        self._tracker = SignalTracker(period_seconds, extension_r, pullback_r,
                                       max_extension_hours, max_pullback_hours)
        self._awaiting_confirm = None  # {'sigdir':, 'R':, 'sig_close':}, set on ANY signal bar
        self.pending_immediate = []

    def on_bar_close(self, bar, bands):
        if self._awaiting_confirm is not None:
            confirm = self._awaiting_confirm
            self._awaiting_confirm = None
            sigdir = confirm['sigdir']
            reversed_next_bar = (bar.c < bar.o) if sigdir == 1 else (bar.c > bar.o)
            if reversed_next_bar:
                self.pending_immediate.append({
                    'dir': -sigdir, 'R': confirm['R'], 'sig_close': confirm['sig_close']})

        if bands is not None:
            u20, l20, u4, l4 = bands
            o, h, l, c = bar.o, bar.h, bar.l, bar.c
            bull = c > o and h >= u20 and h >= u4
            bear = c < o and l <= l20 and l <= l4
            if bull or bear:
                R = abs(c - o)
                if R > 0:
                    self._awaiting_confirm = {'sigdir': 1 if bull else -1, 'R': R, 'sig_close': c}

        self._tracker.on_bar_close(bar, bands)  # mechanical extension/pullback fallback, both directions

    def on_tick(self, ts, bid, ask):
        events = self._tracker.on_tick(ts, bid, ask)
        if self.pending_immediate:
            for setup in self.pending_immediate:
                events.append(TriggerEvent(time=ts, dir=setup['dir'], R=setup['R'],
                                            sig_close=setup['sig_close']))
            self.pending_immediate = []
        return events
