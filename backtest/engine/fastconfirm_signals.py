"""Signal tracker for the "next-bar confirmation" idea on top of the
BUYONLY baseline:

- BULL breakout (would lead to countertrend SELL): skipped entirely,
  same as AllowShort=false in the live BUYONLY EAs.
- BEAR breakout (leads to countertrend BUY): runs TWO paths in parallel
  and whichever fires first wins (PositionManager ignores a second
  entry while a position is already open):
    1. Original mechanical extension(0.95R)+pullback(0.10R) wait,
       unchanged (SignalTracker).
    2. NEW fast path: look at the very next bar after the signal bar.
       If it closes bullish (close > open), enter BUY immediately at
       that bar's close instead of waiting for extension/pullback.
"""

from .signals import SignalTracker, TriggerEvent


class FastConfirmSignalTracker:
    def __init__(self, period_seconds, extension_r=0.95, pullback_r=0.10,
                 max_extension_hours=72, max_pullback_hours=72):
        self._bear_tracker = SignalTracker(period_seconds, extension_r, pullback_r,
                                            max_extension_hours, max_pullback_hours)
        self._awaiting_confirm = None  # set on a bear signal bar's close, resolved on the NEXT bar
        self.pending_immediate = []

    def on_bar_close(self, bar, bands):
        if self._awaiting_confirm is not None:
            confirm = self._awaiting_confirm
            self._awaiting_confirm = None
            if bar.c > bar.o:
                self.pending_immediate.append({'R': confirm['R'], 'sig_close': confirm['sig_close']})

        if bands is None:
            return
        u20, l20, u4, l4 = bands
        o, h, l, c = bar.o, bar.h, bar.l, bar.c
        bear = c < o and l <= l20 and l <= l4
        if bear:
            R = abs(c - o)
            if R > 0:
                self._awaiting_confirm = {'R': R, 'sig_close': c}
            self._bear_tracker.on_bar_close(bar, bands)
        # bull breakout: intentionally skipped (AllowShort=false baseline)

    def on_tick(self, ts, bid, ask):
        events = self._bear_tracker.on_tick(ts, bid, ask)
        if self.pending_immediate:
            for setup in self.pending_immediate:
                events.append(TriggerEvent(time=ts, dir=1, R=setup['R'], sig_close=setup['sig_close']))
            self.pending_immediate = []
        return events
